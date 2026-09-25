// Peeku website: the character, the notch island and the hero background.
(() => {
  'use strict';

  const INK = '#060607';
  const C = { idle:'#d6d6dc', working:'#f5f5f7', question:'oklch(0.8 0.12 250)', permission:'oklch(0.83 0.13 78)', error:'oklch(0.75 0.15 25)', success:'oklch(0.82 0.14 152)', multiple:'oklch(0.83 0.13 78)' };
  const ANIM = { idle:'pipBreath 4.5s ease-in-out infinite', working:'pipBreath 2.2s ease-in-out infinite', question:'pipTilt 2.8s ease-in-out infinite', permission:'pipHop 1.8s cubic-bezier(.3,.7,.4,1) infinite', error:'pipShake 2.6s ease-in-out infinite', success:'pipHop 1.3s cubic-bezier(.3,.7,.4,1) infinite', multiple:'pipHop 1.8s cubic-bezier(.3,.7,.4,1) infinite' };

  // ---- tiny DOM helpers -------------------------------------------------
  const UNITLESS = new Set(['opacity', 'fontWeight', 'lineHeight', 'zIndex']);
  function el(tag, style, kids) {
    const n = document.createElement(tag);
    for (const k in style || {}) {
      const v = style[k];
      n.style[k] = typeof v === 'number' && !UNITLESS.has(k) ? v + 'px' : v;
    }
    for (const kid of kids || []) if (kid != null) n.append(kid);
    return n;
  }
  const esc = (s) => s.replace(/[&<>"]/g, (ch) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[ch]));

  // ---- the character ----------------------------------------------------
  function eyes(state, s, c, box) {
    const glow = `0 0 ${Math.max(2, s * .14)}px ${c}`;
    const mk = (x) => {
      const side = x === 'L' ? 'left' : 'right';
      let w = s * .12, hh = s * .2, t;
      const extra = {};
      if (state === 'permission' || state === 'multiple') { w = s * .14; hh = s * .24; }
      if (state === 'question') hh = x === 'L' ? s * .15 : s * .23;
      if (state === 'error') { w = s * .16; hh = s * .065; extra.transform = `rotate(${x === 'L' ? -22 : 22}deg)`; }
      t = (box.height - hh) / 2;
      if (state === 'idle') { hh = Math.max(1.5, s * .045); t = box.height * .6; extra.opacity = .7; }
      if (state === 'success') {
        w = s * .15; hh = s * .1; t = (box.height - hh) / 2;
        return el('div', { position:'absolute', top:t, [side]:0, width:w, height:hh, boxSizing:'border-box', border:`${Math.max(1.5, s * .045)}px solid ${c}`, borderBottom:'none', borderRadius:`${w}px ${w}px 0 0`, filter:`drop-shadow(0 0 ${s * .07}px ${c})` });
      }
      return el('div', { position:'absolute', top:t, [side]:0, width:w, height:hh, borderRadius:Math.min(w, hh) / 2, background:c, boxShadow:glow, ...extra });
    };
    const blink = state !== 'idle' && state !== 'success' && state !== 'error';
    return el('div', { position:'absolute', ...box, animation: state === 'working' ? 'pipGlance 3.4s ease-in-out infinite' : 'none' }, [
      el('div', { position:'absolute', inset:0, animation: blink ? 'pipBlink 5.5s infinite' : 'none' }, [mk('L'), mk('R')])
    ]);
  }

  function extras(state, s, c, o) {
    const k = [];
    if (o.noBadge) return k;
    if (state === 'permission' || state === 'multiple') {
      const b = Math.max(13, s * .32);
      k.push(el('div', { position:'absolute', top:s * .02, right:-s * .1, width:b, height:b, borderRadius:'50%', background:c, color:'#1b1406', fontSize:b * .62, fontWeight:700, display:'flex', alignItems:'center', justifyContent:'center', boxShadow:`0 0 0 2px ${o.ring || '#000'}`, lineHeight:1 }, [state === 'multiple' ? '3' : '!']));
    }
    if (state === 'question') k.push(el('div', { position:'absolute', top:-s * .24, right:-s * .16, fontSize:s * .38, fontWeight:700, color:c, textShadow:`0 0 ${s * .12}px ${c}`, animation:'pipBob 1.6s ease-in-out infinite', lineHeight:1 }, ['?']));
    if (state === 'success') {
      const d = Math.max(3, s * .1);
      k.push(el('div', { position:'absolute', top:-s * .04, left:-s * .1, width:d, height:d, background:c, animation:'pipTwinkle 1.4s ease-in-out infinite' }));
      k.push(el('div', { position:'absolute', top:s * .16, right:-s * .16, width:d * .8, height:d * .8, background:c, animation:'pipTwinkle 1.4s .5s ease-in-out infinite' }));
    }
    if (o.z && state === 'idle') {
      k.push(el('div', { position:'absolute', top:0, right:-s * .1, fontSize:s * .22, fontWeight:600, color:'rgba(235,235,245,.55)', animation:'pipZ 3s ease-out infinite' }, ['z']));
    }
    return k;
  }

  function pip(state, s, o = {}) {
    const c = C[state], rim = !o.flat;
    const ear = (side) => el('div', { position:'absolute', top:s * .04, [side]:s * .13, width:s * .22, height:s * .28, background:INK, borderRadius:'50%', transform:`rotate(${side === 'left' ? -20 : 20}deg)`, boxShadow: rim ? 'inset 0 1px 1px rgba(255,255,255,.2)' : 'none' });
    return el('div', { position:'relative', width:s, height:s, flex:'none', animation:o.still ? 'none' : ANIM[state], transformOrigin:'50% 100%' }, [
      ear('left'), ear('right'),
      el('div', { position:'absolute', left:0, top:s * .14, width:s, height:s * .82, background:INK, borderRadius:'50% 50% 46% 46% / 60% 60% 40% 40%', boxShadow: rim ? 'inset 0 1px 1px rgba(255,255,255,.2), inset 0 -4px 10px rgba(255,255,255,.04), 0 0 0 .5px rgba(255,255,255,.1)' : 'none' }),
      eyes(state, s, c, { left:s * .29, top:s * .44, width:s * .42, height:s * .26 }),
      ...extras(state, s, c, o)
    ]);
  }

  function group(s) {
    return el('div', { position:'relative', width:s * 1.7, height:s }, [
      el('div', { position:'absolute', left:0, top:0, opacity:.5, transform:'scale(.68)', transformOrigin:'0 100%' }, [pip('question', s, { noBadge:true, still:true })]),
      el('div', { position:'absolute', right:0, top:0, opacity:.5, transform:'scale(.68)', transformOrigin:'100% 100%' }, [pip('error', s, { noBadge:true, still:true })]),
      el('div', { position:'absolute', left:s * .35, top:0 }, [pip('multiple', s)])
    ]);
  }

  // Static characters: <div data-pip="state" data-size="56" data-opts="flat,noBadge"></div>
  document.querySelectorAll('[data-pip]').forEach((slot) => {
    const state = slot.dataset.pip, s = +slot.dataset.size;
    if (state === 'group') { slot.replaceWith(group(s)); return; }
    const o = {};
    (slot.dataset.opts || '').split(',').filter(Boolean).forEach((f) => { o[f] = true; });
    if (slot.dataset.ring) o.ring = slot.dataset.ring;
    slot.replaceWith(pip(state, s, o));
  });

  // ---- install: copy the xattr command ---------------------------------
  const copyBtn = document.querySelector('.copy-cmd');
  if (copyBtn) {
    let reset;
    copyBtn.addEventListener('click', () => {
      navigator.clipboard?.writeText('xattr -dr com.apple.quarantine /Applications/Peeku.app').catch(() => {});
      copyBtn.textContent = 'Copied';
      clearTimeout(reset);
      reset = setTimeout(() => { copyBtn.textContent = 'Copy'; }, 1500);
    });
  }

  // ---- scroll reveals: fade sections up as they enter the viewport -----
  // Elements entering together are staggered so rows cascade in.
  if (document.documentElement.classList.contains('reveal-on')) {
    const TEXT = '.problem > p, .flow-text, .features-title, .tile, .closer-head > *, .moods > h2, .moods > p, .mood, .light-row .flow-text, .how-intro, .source, .shortcuts-intro, .keys > div, .install-intro, .install-steps';
    const MEDIA = '.shot, .shots figure';
    document.querySelectorAll(TEXT).forEach((n) => n.classList.add('reveal'));
    document.querySelectorAll(MEDIA).forEach((n) => n.classList.add('reveal', 'media'));
    const io = new IntersectionObserver((entries) => {
      let i = 0;
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.style.transitionDelay = Math.min(i++, 6) * 70 + 'ms';
        e.target.classList.add('in');
        io.unobserve(e.target);
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: .12 });
    document.querySelectorAll('.reveal').forEach((n) => io.observe(n));
  }

  // ---- the notch island -------------------------------------------------
  const EV = {
    permission:{ state:'permission', tag:'Permission', env:'iTerm · Tab 1', title:'Claude needs your permission', meta:'payments-api · feat/stripe-v17 · 12s ago', code:'$ npm install stripe@17.2.0', cta:'Open Session', toast:'Switched to iTerm · Tab 1 · payments-api' },
    question:{ state:'question', tag:'Question', env:'VS Code · Window 1', title:'Claude has a question', meta:'dashboard-v2 · main · 2m ago', code:'Reuse <Popover> for chart tooltips, or build a new <ChartTooltip>?', cta:'Open Session', toast:'Switched to VS Code · dashboard-v2' },
    error:{ state:'error', tag:'Blocked', env:'iTerm · Tab 2', title:'Claude hit an error', meta:'infra-terraform · chore/tf-1.9 · 6m ago', code:'Error acquiring the state lock', cta:'Open Session', toast:'Switched to iTerm · Tab 2 · infra-terraform' },
    success:{ state:'success', tag:'Finished', env:'iTerm · Tab 3', title:'Claude finished', meta:'docs-site · main · 2m 41s', code:'Migrated 14 pages to MDX · build passes', cta:'Open Session', toast:'Switched to iTerm · Tab 3 · docs-site' },
    usage:{ state:'permission', tag:'Usage', env:'Claude Code', title:'Claude reached your usage alert', meta:'5-hour limit · resets in 2h 13m', code:'92% used · alert at 90%', cta:'Show Usage', toast:'Opened the Usage tab' }
  };
  const ORDER = ['permission', 'question', 'error', 'success', 'usage'];

  const hero = document.querySelector('.hero');
  const island = document.querySelector('.island');
  if (!hero || !island) return;
  const islandInner = island.querySelector('.island-inner');
  const glow = hero.querySelector('.hero-glow-orb');
  const toastSlot = document.querySelector('.toast-slot');
  const chips = [...document.querySelectorAll('.chip[data-ev]')];
  const ghosts = [...hero.querySelectorAll('.ghost-win[data-ev]')];

  const st = { phase:'working', ev:'permission', idx:0 };
  let timers = [];
  const after = (fn, ms) => { timers.push(setTimeout(fn, ms)); };
  const clear = () => { timers.forEach(clearTimeout); timers = []; };

  function trigger(ev) {
    clear();
    Object.assign(st, { phase:'peek', ev, idx:ORDER.indexOf(ev) });
    render();
    after(() => { st.phase = 'alert'; render(); }, 720);
    after(() => collapse(false), 5200);
  }

  function collapse(opened) {
    clear();
    const e = EV[st.ev];
    st.phase = 'working';
    render();
    showToast(opened ? e.toast : '');
    if (opened) after(() => showToast(''), 1850);
    after(() => trigger(ORDER[(st.idx + 1) % ORDER.length]), 2600);
  }

  function showToast(text) {
    toastSlot.replaceChildren();
    if (!text) return;
    toastSlot.append(el('div', {}, [text]));
    toastSlot.firstChild.className = 'toast';
  }

  const stop = (f) => (x) => { x.stopPropagation(); f(); };

  function islandContent() {
    const e = EV[st.ev];
    if (st.phase === 'working') {
      const wing = el('div', {}, [pip('working', 22, { flat:true, noBadge:true })]);
      wing.className = 'isl-wing';
      const right = document.createElement('div');
      right.className = 'isl-count';
      right.innerHTML = '<i class="isl-spinner"></i><span>5</span>';
      return [wing, right];
    }
    if (st.phase === 'peek') {
      const drop = el('div', {}, [pip(e.state, 30, { flat:true, noBadge:true })]);
      drop.className = 'isl-drop';
      return [drop];
    }
    const box = document.createElement('div');
    box.className = 'isl-alert';
    box.style.setProperty('--ev', C[e.state]);
    box.innerHTML =
      `<div class="isl-head"><span class="isl-tag"><i></i>${esc(e.tag)}</span><span class="isl-env">${esc(e.env)}</span></div>` +
      '<div class="isl-body"><div class="isl-pip"></div><div class="isl-text">' +
      `<div class="isl-title">${esc(e.title)}</div>` +
      `<div class="isl-meta">${esc(e.meta)}</div>` +
      `<div class="isl-code">${esc(e.code)}</div>` +
      `<div class="isl-actions"><button type="button" class="isl-open">${esc(e.cta)}<span>↵</span></button><button type="button" class="isl-later">Later</button></div>` +
      '</div></div>';
    box.querySelector('.isl-pip').append(pip(e.state, 50));
    box.querySelector('.isl-open').addEventListener('click', stop(() => collapse(true)));
    box.querySelector('.isl-later').addEventListener('click', stop(() => collapse(false)));
    return [box];
  }

  function render() {
    const { phase, ev } = st;
    const e = EV[ev];
    island.dataset.phase = phase;
    islandInner.replaceChildren(...islandContent());

    hero.style.setProperty('--glow', phase === 'working' ? '#5b6a9a' : C[e.state]);
    glow.style.opacity = phase === 'alert' ? .32 : phase === 'peek' ? .26 : .16;

    for (const g of ghosts) {
      const id = g.dataset.ev;
      const on = phase !== 'working' && ev === id;
      const any = phase !== 'working' && ev !== 'usage';
      const c = C[EV[id].state];
      g.style.opacity = on ? 1 : any ? .38 : .55;
      g.style.boxShadow = on
        ? `0 0 0 1.5px ${c}, 0 0 50px color-mix(in oklch, ${c} 35%, transparent), 0 30px 60px rgba(0,0,0,.5)`
        : '';
    }
    for (const chip of chips) chip.classList.toggle('on', chip.dataset.ev === ev && phase !== 'working');
  }

  island.addEventListener('click', () => {
    if (st.phase === 'working') trigger(ORDER[st.idx % ORDER.length]);
  });
  chips.forEach((chip) => chip.addEventListener('click', () => trigger(chip.dataset.ev)));

  // Rising motes in the glow color: [left%, top%, size, dx, duration, delay]
  const MOTES = [[49.2,68.0,2.3,1,8.7,-6.2],[50.5,43.9,4.2,-1,11.1,-5.8],[31.9,79.1,3.6,29,7.5,-7.0],[27.7,73.6,2.4,36,10.9,-6.8],[22.8,42.5,4.3,44,13.8,-1.7],[45.3,87.8,2.5,8,9.9,-7.7],[64.4,54.0,2.4,-23,13.9,-6.2],[27.5,67.4,2.8,36,8.1,-10.8],[37.5,57.5,2.2,20,13.5,-3.3],[82.3,63.5,2.6,-52,11.2,-5.6],[71.7,72.6,2.3,-35,8.6,-6.3],[15.6,42.4,3.0,55,11.8,-9.1],[88.2,56.2,3.1,-61,10.5,-6.1],[78.4,62.5,3.1,-45,8.8,-3.3],[70.4,46.6,2.7,-33,12.4,-12.0],[89.3,86.3,4.2,-63,12.2,-9.0]];
  const motes = hero.querySelector('.hero-motes');
  for (const [l, t, sz, dx, dur, delay] of MOTES) {
    const m = el('i', { left:l + '%', top:t + '%', width:sz, height:sz, animation:`rise ${dur}s linear ${delay}s infinite` });
    m.style.setProperty('--dx', dx + 'px');
    motes.append(m);
  }

  render();
  after(() => trigger(ORDER[0]), 1600);
})();
