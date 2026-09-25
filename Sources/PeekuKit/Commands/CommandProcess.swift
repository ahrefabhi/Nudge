import Darwin
import Foundation

/// One run of a quick command: the user's shell in a pseudo-terminal of its own, so tools act
/// as they would in a terminal tab and can ask questions (the user answers from the output
/// window). The shell leads a new session; stopping signals it, its process group, every
/// descendant and everything still attached to the terminal, so `npm run dev` doesn't leave its
/// dev server holding the port.
final class CommandProcess: @unchecked Sendable {
    enum Termination: Equatable, Sendable {
        case exited(Int32)
        case signaled(Int32)

        /// A shell-style status: the exit code, or 128 plus the signal.
        var code: Int32 {
            switch self {
            case .exited(let code): code
            case .signaled(let signal): 128 + signal
            }
        }
    }

    struct SpawnError: Error, CustomStringConvertible {
        let description: String
    }

    /// Wide enough that tools don't wrap their output early.
    static let terminalSize = winsize(ws_row: 40, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)

    let pid: pid_t
    /// The leader's start time, to tell it apart from a later process given the same pid.
    let started: UInt64
    /// Peeku's side of the terminal: output is read from it and replies written to it.
    private let terminal: Int32
    /// The terminal's device, to find every process still attached to it.
    private let device: dev_t
    private let lock = NSLock()
    private var descendants: Set<pid_t> = []
    private var ended = false
    private var closed = false

    private init(pid: pid_t, terminal: Int32, device: dev_t) {
        self.pid = pid
        self.terminal = terminal
        self.device = device
        started = Self.startTime(of: pid) ?? 0
    }

    deinit {
        close(terminal)
    }

    /// Starts `command` through the user's shell in `directory`. Interactive and login, like a
    /// new terminal tab, so the PATH from their `.zshrc` (nvm, pyenv, …) applies.
    static func spawn(_ command: String, in directory: String, environment: [String: String]) throws -> CommandProcess {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SpawnError(description: "The folder \(directory) doesn't exist.")
        }
        var master: Int32 = 0, slave: Int32 = 0
        var size = terminalSize
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            throw SpawnError(description: "Couldn't open a terminal: \(String(cString: strerror(errno)))")
        }
        var info = stat()
        fstat(slave, &info)
        let slavePath = String(cString: ptsname(master))
        // Kept open until the child has it, or the terminal resets and forgets its size.
        defer { close(slave) }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, slavePath, O_RDWR | O_NOCTTY, 0)
        posix_spawn_file_actions_adddup2(&actions, 0, 1)
        posix_spawn_file_actions_adddup2(&actions, 0, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A new session (so pgid = sid = pid); no descriptors from Peeku besides 0–2; default signal handling.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                     | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setsigmask(&attributes, &none)

        // posix_spawn opens files before starting the new session, so that open can't make the
        // terminal the controlling one. A session leader's own open does, so /bin/sh reopens it,
        // then becomes the user's shell. The controlling terminal is what lets Ctrl-C from the
        // output window reach the foreground job, and tools see a real terminal to ask questions in.
        let shell = userShell
        let argv = ["/bin/sh", "-c", #"exec <>"$1" >&0 2>&0; shift; exec "$@""#, "peeku-command", slavePath,
                    shell, "-l", "-i", "-c", command]
        let envp = environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let status = withCStrings(argv) { argv in
            withCStrings(envp) { envp in posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, envp) }
        }
        guard status == 0 else {
            close(master)
            throw SpawnError(description: "Couldn't start \(shell): \(String(cString: strerror(status)))")
        }
        return CommandProcess(pid: pid, terminal: master, device: info.st_rdev)
    }

    /// Calls `handler` on a background thread with each chunk of output, then once with empty
    /// data when nothing has the terminal open anymore.
    func readOutput(_ handler: @escaping @Sendable (Data) -> Void) {
        Thread.detachNewThread { [self] in
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = read(terminal, &buffer, buffer.count)
                if count > 0 {
                    handler(Data(buffer[0..<count]))
                } else if count < 0 && (errno == EINTR || errno == EAGAIN) {
                    continue
                } else {
                    // A terminal reports EIO, not end of file, once its last user closes it.
                    break
                }
            }
            lock.withLock { closed = true }
            handler(Data())
        }
    }

    /// Sends a reply or a key, e.g. "y\r" or Ctrl-C's "\u{03}", as if typed in the terminal.
    func write(_ text: String) {
        guard !lock.withLock({ closed }) else { return }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(terminal, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 { if errno == EINTR { continue } else { return } }
                offset += written
            }
        }
    }

    /// Waits on a background thread and calls `handler` there once the shell exits.
    func waitForExit(_ handler: @escaping @Sendable (Termination) -> Void) {
        let pid = pid
        Thread.detachNewThread { [self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            // What <sys/wait.h>'s WIFEXITED and friends compute.
            let signal = status & 0x7f
            let termination: Termination = signal == 0 ? .exited((status >> 8) & 0xff) : .signaled(signal)
            lock.withLock { ended = true }
            handler(termination)
        }
    }

    var hasEnded: Bool { lock.withLock { ended } }

    /// Signals the process group, every process descended from the shell and everything still
    /// attached to its terminal. With a terminal, zsh gives each job its own process group, and
    /// once the shell exits its children are handed to launchd, so the tree is remembered.
    func signal(_ signal: Int32) {
        let tree = lock.withLock {
            if !ended { descendants.formUnion(Self.descendants(of: pid)) }
            descendants.formUnion(Self.attached(to: device))
            return descendants
        }
        kill(-pid, signal)
        for child in tree { kill(child, signal) }
    }

    /// Whether anything Peeku started for this run is still alive.
    var anythingAlive: Bool {
        if !hasEnded { return true }
        if kill(-pid, 0) == 0 || !Self.attached(to: device).isEmpty { return true }
        return lock.withLock { descendants }.contains { kill($0, 0) == 0 }
    }

    // MARK: Darwin

    /// The login shell from the user database. `$SHELL` isn't set for an app opened from Finder.
    static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    static func startTime(of pid: pid_t) -> UInt64? {
        bsdInfo(pid).map { $0.pbi_start_tvsec }
    }

    /// Whether `pid` still leads the process group Peeku started at `started`.
    static func isLeader(_ pid: pid_t, started: UInt64) -> Bool {
        guard let info = bsdInfo(pid) else { return false }
        return info.pbi_start_tvsec == started && info.pbi_pgid == UInt32(pid)
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 512)
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return buffer.prefix(min(Int(count), buffer.count)).filter { $0 > 0 }
    }

    /// Processes whose controlling terminal is `device`.
    static func attached(to device: dev_t) -> Set<pid_t> {
        var buffer = [pid_t](repeating: 0, count: 1024)
        let bytes = proc_listpids(UInt32(PROC_TTY_ONLY), UInt32(bitPattern: device), &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return Set(buffer.prefix(min(Int(bytes) / MemoryLayout<pid_t>.size, buffer.count)).filter { $0 > 0 })
    }

    static func descendants(of pid: pid_t) -> Set<pid_t> {
        var found: Set<pid_t> = []
        var queue = children(of: pid)
        while let next = queue.popLast() {
            guard found.insert(next).inserted else { continue }
            queue += children(of: next)
        }
        return found
    }
}

/// Calls `body` with a NULL-terminated C array of `strings`, as `posix_spawn` wants.
private func withCStrings<R>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return body(pointers)
}
