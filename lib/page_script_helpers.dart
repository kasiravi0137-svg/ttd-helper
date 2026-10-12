// Page script, part 1: helper functions that run inside the TTD page.
const kJsHelpers = r'''
(function () {
  if (window.__ttd && window.__ttd.v === 4) return;
  const state = (window.__ttd && window.__ttd.state) || { sawDialog: false, gone: 0, iconClicks: 0 };

  // ---------- small helpers ----------
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const norm = (s) =>
    (s || '')
      .toString()
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  const vis = (e) => {
    if (!e || !e.getBoundingClientRect) return false;
    const r = e.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const s = getComputedStyle(e);
    return s.visibility !== 'hidden' && s.display !== 'none';
  };
  const has = (text, keys) => {
    const x = ' ' + norm(text) + ' ';
    return keys.some((k) => x.includes(' ' + norm(k) + ' '));
  };
  const post = (o) => {
    try {
      TTD.postMessage(JSON.stringify(o));
    } catch (e) {}
  };
  const done = (ok, msg, extra) =>
    post(Object.assign({ type: 'result', ok: !!ok, msg: msg || '' }, extra || {}));
  const run = async (fn) => {
    try {
      await fn();
    } catch (e) {
      done(false, String(e));
    }
  };
  const PE = typeof PointerEvent === 'function' ? PointerEvent : MouseEvent;

  function fireClick(el) {
    try {
      el.scrollIntoView({ block: 'center' });
    } catch (e) {}
    const r = el.getBoundingClientRect();
    const o = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: r.left + r.width / 2,
      clientY: r.top + r.height / 2,
    };
    el.dispatchEvent(new PE('pointerdown', o));
    el.dispatchEvent(new MouseEvent('mousedown', o));
    el.dispatchEvent(new PE('pointerup', o));
    el.dispatchEvent(new MouseEvent('mouseup', o));
    el.dispatchEvent(new MouseEvent('click', o));
  }

  const PHONE = ['mobile', 'mobile number', 'registered mobile number', 'phone', 'phone number'];

  function labelOf(el) {
    let t = [
      el.placeholder,
      el.getAttribute('aria-label'),
      el.getAttribute('formcontrolname'),
      el.getAttribute('name'),
    ]
      .filter(Boolean)
      .join(' ');
    let lab = null;
    if (el.id) {
      try {
        lab = document.querySelector('label[for="' + el.id + '"]');
      } catch (e) {}
    }
    if (!lab) {
      const ff = el.closest('mat-form-field,.mat-form-field,.mat-mdc-form-field');
      if (ff) lab = ff.querySelector('label,mat-label');
    }
    if (!lab && el.parentElement) lab = el.parentElement.querySelector('label');
    if (lab) t += ' ' + lab.innerText;
    return t;
  }

  function setVal(el, v) {
    el.scrollIntoView({ block: 'center' });
    el.focus();
    let ok = false;
    // Typing through execCommand fires real input events, which frameworks trust most.
    try {
      if (typeof document.execCommand === 'function') {
        if (el.select) el.select();
        ok = document.execCommand('insertText', false, v) && el.value === v;
      }
    } catch (e) {}
    if (!ok) {
      const proto =
        el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const d = Object.getOwnPropertyDescriptor(proto, 'value');
      d.set.call(el, v);
      el.dispatchEvent(new Event('input', { bubbles: true }));
    }
    el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  const SKIP = ['hidden', 'checkbox', 'radio', 'button', 'submit', 'file'];
  const inputs = (keys) =>
    [...document.querySelectorAll('input,textarea')].filter(
      (e) => vis(e) && !SKIP.includes(e.type) && has(labelOf(e), keys)
    );
  const selects = (keys) =>
    [...document.querySelectorAll('select,mat-select,[role=combobox]')].filter(
      (e) => e.tagName !== 'INPUT' && vis(e) && has(labelOf(e), keys)
    );

  function findText(texts, exact) {
    const want = texts.map(norm);
    let best = null;
    let bl = 1e9;
    document
      .querySelectorAll(
        'button,a,li,span,div,label,mat-option,[role=button],[role=option],[role=menuitem],[role=tab]'
      )
      .forEach((e) => {
        if (!vis(e)) return;
        const t = norm(e.innerText);
        if (!t || t.length > 60) return;
        const ok = want.some((w) =>
          exact ? t === w : t === w || (' ' + t + ' ').includes(' ' + w + ' ')
        );
        if (ok && t.length <= bl) {
          best = e;
          bl = t.length;
        }
      });
    return best;
  }

  function clickText(texts, exact) {
    const best = findText(texts, exact);
    if (best) {
      best.scrollIntoView({ block: 'center' });
      best.click();
      return true;
    }
    return false;
  }

  function isDisabled(el) {
    const b = el.closest('button,[role=button]') || el;
    return (
      b.disabled === true ||
      b.getAttribute('aria-disabled') === 'true' ||
      /disabled/i.test(b.className || '') ||
      getComputedStyle(b).pointerEvents === 'none'
    );
  }

  // ---------- typing (works with masked / framework inputs) ----------
  const digits = (s) => (s || '').replace(/\D/g, '');
  function sameVal(cur, want) {
    if (digits(want).length >= 6) return digits(cur).endsWith(digits(want));
    const a = norm(cur);
    const b = norm(want);
    return a === b || (b.length > 0 && a.includes(b));
  }
  function setNative(el, v) {
    const proto =
      el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  }
  async function typeInto(el, text, keysOnly) {
    el.scrollIntoView({ block: 'center' });
    el.focus();
    try {
      el.click();
    } catch (e) {}
    if (!keysOnly) {
      try {
        el.select();
        document.execCommand('delete');
        document.execCommand('insertText', false, text);
      } catch (e) {}
      await sleep(200);
      if (sameVal(el.value, text)) return true;
    }
    // fall back to key-by-key typing
    setNative(el, '');
    el.dispatchEvent(new Event('input', { bubbles: true }));
    for (const ch of text) {
      el.dispatchEvent(new KeyboardEvent('keydown', { key: ch, bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keypress', { key: ch, bubbles: true }));
      el.dispatchEvent(
        new InputEvent('beforeinput', { data: ch, inputType: 'insertText', bubbles: true, cancelable: true })
      );
      setNative(el, el.value + ch);
      el.dispatchEvent(new InputEvent('input', { data: ch, inputType: 'insertText', bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keyup', { key: ch, bubbles: true }));
      await sleep(45);
    }
    el.dispatchEvent(new Event('change', { bubbles: true }));
    await sleep(150);
    return sameVal(el.value, text);
  }
  // Reach into the page's own framework (Angular form control or React onChange).
  function ngControlFor(el) {
    const ctx = el.__ngContext__;
    if (!ctx || typeof ctx !== 'object') return null;
    const seen = new Set();
    const stack = [ctx];
    const found = [];
    let n = 0;
    while (stack.length && n++ < 6000) {
      const x = stack.pop();
      if (!x || typeof x !== 'object' || seen.has(x)) continue;
      seen.add(x);
      if (typeof Node !== 'undefined' && x instanceof Node) continue;
      if (x.control && typeof x.control.setValue === 'function') found.push(x);
      else if (typeof x.setValue === 'function' && 'valueChanges' in x) found.push({ control: x });
      if (Array.isArray(x)) {
        for (const v of x) stack.push(v);
      } else {
        for (const k of Object.keys(x)) {
          try {
            stack.push(x[k]);
          } catch (e) {}
        }
      }
    }
    const host = (d) => {
      const a = d.valueAccessor || d;
      const e = a._elementRef || a.elementRef || a._el || a.el;
      return e && (e.nativeElement === el || e === el);
    };
    let pick = found.find(host);
    if (!pick) pick = found.find((d) => /mobile|phone|number/i.test(String(d.name || d.path || '')));
    if (!pick && found.length === 1) pick = found[0];
    return pick ? pick.control : null;
  }
  function reactPropsFor(el) {
    const k = Object.keys(el).find((x) => x.startsWith('__reactProps$'));
    return k ? el[k] : null;
  }
  function frameworkHint(el) {
    const h = [];
    if (el.__ngContext__ !== undefined) h.push('angular');
    if (reactPropsFor(el)) h.push('react');
    if (el.closest && el.closest('ion-input')) h.push('ionic');
    if (el.closest && el.closest('mat-form-field')) h.push('material');
    return h.join('+') || 'plain';
  }

  // Phone boxes with a "(+91)" mask update late and may ignore plain value changes,
  // so type slowly, wait, and check what really ended up in the box.
  async function typePhone(el, p) {
    const prefix = ((el.value || '').match(/^\D*91\D*/) || [''])[0];
    const rest = () => {
      let d = digits(el.value);
      if (/\(\s*\+?\s*91|\+\s*91/.test(el.value || '')) d = d.slice(2);
      return d;
    };
    const caretEnd = () => {
      try {
        el.setSelectionRange(el.value.length, el.value.length);
      } catch (e) {}
    };
    const clearDigits = async () => {
      el.focus();
      try {
        el.setSelectionRange(prefix.length, el.value.length);
        document.execCommand('delete');
      } catch (e) {}
      await sleep(500);
      if (rest().length) {
        setNative(el, prefix);
        el.dispatchEvent(new InputEvent('input', { inputType: 'deleteContentBackward', bubbles: true }));
        await sleep(500);
      }
    };
    const kd = (ch) => {
      const kc = 48 + Number(ch);
      return { key: ch, code: 'Digit' + ch, keyCode: kc, which: kc, bubbles: true, cancelable: true };
    };
    const methods = {
      A: async () => {
        for (const ch of p) {
          try {
            document.execCommand('insertText', false, ch);
          } catch (e) {}
          await sleep(100);
          caretEnd();
        }
      },
      B: async () => {
        for (const ch of p) {
          el.dispatchEvent(new KeyboardEvent('keydown', kd(ch)));
          el.dispatchEvent(new KeyboardEvent('keypress', kd(ch)));
          el.dispatchEvent(
            new InputEvent('beforeinput', { data: ch, inputType: 'insertText', bubbles: true, cancelable: true })
          );
          setNative(el, el.value + ch);
          caretEnd();
          el.dispatchEvent(new InputEvent('input', { data: ch, inputType: 'insertText', bubbles: true }));
          el.dispatchEvent(new KeyboardEvent('keyup', kd(ch)));
          await sleep(130);
        }
      },
      E: async () => {
        const ctrl = ngControlFor(el);
        if (ctrl) {
          try {
            ctrl.setValue(p);
            if (ctrl.markAsDirty) ctrl.markAsDirty();
            if (ctrl.markAsTouched) ctrl.markAsTouched();
          } catch (e) {}
          return;
        }
        const pr = reactPropsFor(el);
        if (pr && typeof pr.onChange === 'function') {
          setNative(el, prefix + p);
          try {
            pr.onChange({
              target: el,
              currentTarget: el,
              type: 'change',
              persist() {},
              preventDefault() {},
              stopPropagation() {},
              nativeEvent: new InputEvent('input', { data: p, bubbles: true }),
            });
          } catch (e) {}
        }
      },
      C: async () => {
        setNative(el, prefix + p);
        el.dispatchEvent(new InputEvent('input', { data: p, inputType: 'insertFromPaste', bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      },
      D: async () => {
        setNative(el, p);
        el.dispatchEvent(new InputEvent('input', { data: p, inputType: 'insertText', bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      },
    };
    el.scrollIntoView({ block: 'center' });
    el.focus();
    try {
      el.click();
    } catch (e) {}
    await sleep(400);
    if (rest() === p) return { ok: true, how: 'already' };
    const log = [];
    for (const k of ['A', 'E', 'B', 'C', 'D']) {
      for (let round = 0; round < 2; round++) {
        if (rest().length) await clearDigits();
        el.focus();
        caretEnd();
        post({ type: 'progress', msg: 'Typing the number (method ' + k + '), box shows "' + el.value + '"' });
        await methods[k]();
        await sleep(850);
        if (rest() === p) return { ok: true, how: k };
        log.push(k + round + '="' + el.value + '"');
        // nothing accepted at all: another round of the same method will not help
        if (!rest().length) break;
      }
    }
    if (rest().length) await clearDigits();
    const attrs = ['type', 'maxlength', 'placeholder', 'inputmode', 'readonly', 'mask', 'pattern']
      .map((a) => (el.hasAttribute(a) ? a + '=' + el.getAttribute(a) : ''))
      .filter(Boolean)
      .join(' ');
    const par = el.parentElement;
    const info =
      'fw=' + frameworkHint(el) +
      ' cls=' + String(el.className || '').slice(0, 60) +
      ' parent=' + (par ? par.tagName.toLowerCase() + '.' + String(par.className || '').slice(0, 40) : '');
    return { ok: false, how: info + ' | ' + attrs + ' | ' + log.join(' ') };
  }
  async function enter(el, value) {
    setVal(el, value);
    await sleep(150);
    if (sameVal(el.value, value)) return true;
    return await typeInto(el, value);
  }

  function present(texts) {
    const want = texts.map(norm);
    return [
      ...document.querySelectorAll('a,button,span,li,div,p,h1,h2,h3,h4,[role=button],[role=menuitem]'),
    ].some((e) => {
      if (!vis(e)) return false;
      const t = norm(e.innerText);
      return t && t.length < 40 && want.some((w) => t === w);
    });
  }

  // ---------- dropdowns (works with native, mat-select and custom ones) ----------
  function labelEls(keys) {
    const want = keys.map(norm);
    const c = [];
    document
      .querySelectorAll('label,mat-label,span,div,p,legend,h1,h2,h3,h4,h5,h6')
      .forEach((e) => {
        if (!vis(e)) return;
        const t = norm(e.innerText);
        if (t && t.length < 40 && want.includes(t)) c.push(e);
      });
    return c.filter((e) => !c.some((o) => o !== e && e.contains(o)));
  }

  function controlFor(lab) {
    let c = lab;
    for (let i = 0; i < 5 && c.parentElement; i++) {
      c = c.parentElement;
      const r = c.getBoundingClientRect();
      if (r.height >= 40 && r.height <= 170) return c;
    }
    return lab.parentElement || lab;
  }

  const OPT_STRICT = 'mat-option,[role=option],li,.mat-option,.mat-mdc-option,.option';
  const OPT_LOOSE = OPT_STRICT + ',.dropdown-item,button,a,div,span,p';

  function findOption(value, ctl, strict) {
    const w = norm(value);
    const pool = [...document.querySelectorAll(strict ? OPT_STRICT : OPT_LOOSE)].filter(
      (e) => vis(e) && !ctl.contains(e) && !e.contains(ctl)
    );
    const t = (e) => norm(e.innerText);
    let c = pool.filter((e) => t(e) === w);
    if (!c.length && !strict) {
      c = pool.filter((e) => {
        const x = t(e);
        return x && x.length <= w.length + 6 && x.startsWith(w.slice(0, 4));
      });
    }
    return c.length ? c[c.length - 1] : null;
  }

  function optionTexts(ctl) {
    return [...document.querySelectorAll('mat-option,[role=option],li')]
      .filter((e) => vis(e) && !ctl.contains(e))
      .map((e) => (e.innerText || '').trim())
      .filter((s) => s && s.length < 30);
  }

  async function openAndPick(ctl, value, strict) {
    ctl.scrollIntoView({ block: 'center' });
    await sleep(250);
    const r = ctl.getBoundingClientRect();
    const hit =
      (document.elementFromPoint && document.elementFromPoint(r.left + r.width * 0.5, r.top + r.height * 0.7)) ||
      ctl;
    fireClick(hit);
    await sleep(700);
    let opt = findOption(value, ctl, strict);
    if (!opt) {
      const trig = ctl.querySelector(
        'mat-select,[role=combobox],[role=button],.mat-select-trigger,.mat-mdc-select-trigger,mat-icon,svg,button'
      );
      if (trig) {
        fireClick(trig);
        await sleep(700);
        opt = findOption(value, ctl, strict);
      }
    }
    if (!opt) {
      const seen = optionTexts(ctl).slice(0, 6).join(' | ');
      return { ok: false, why: 'option "' + value + '" not found' + (seen ? ' (page shows: ' + seen + ')' : '') };
    }
    fireClick(opt);
    await sleep(500);
    return { ok: true };
  }

  async function pickFrom(el, value) {
    const w = norm(value);
    if (el.tagName === 'SELECT') {
      const o =
        [...el.options].find((x) => norm(x.text) === w) ||
        [...el.options].find((x) => norm(x.text).includes(w));
      if (!o) return false;
      el.value = o.value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }
    el.scrollIntoView({ block: 'center' });
    fireClick(el);
    await sleep(600);
    const o = findOption(value, el, true);
    if (!o) return false;
    fireClick(o);
    await sleep(400);
    return true;
  }

  async function fillDropdown(keys, value, idx) {
    if (!value) return { ok: false, why: 'no value' };
    const s = selects(keys)[idx];
    if (s && (await pickFrom(s, value))) return { ok: true };
    const labs = labelEls(keys);
    if (!labs[idx]) return { ok: false, why: 'field not found' };
    const lab = labs[idx];
    const ctl = controlFor(lab);
    const res = await openAndPick(ctl, value, false);
    if (!res.ok) return res;
    const after = norm(ctl.innerText);
    if (after === norm(lab.innerText) || after.length <= norm(lab.innerText).length) {
      return { ok: false, why: 'tapped but nothing was selected' };
    }
    return { ok: true };
  }

  async function fillAny(keys, value, idx) {
    if (!value) return false;
    const i = inputs(keys)[idx];
    if (!i || i.disabled) return false;
    await enter(i, value);
    await sleep(450);
    const w = norm(value);
    const opts = [...document.querySelectorAll('mat-option,[role=option]')].filter(vis);
    const o =
      opts.find((e) => norm(e.innerText) === w) ||
      opts.find((e) => norm(e.innerText).includes(w));
    if (o) {
      fireClick(o);
      await sleep(300);
    }
    return true;
  }

  // ---------- forms ----------
  async function fillDevotees(list) {
    let n = 0;
    const fails = [];
    for (let i = 0; i < list.length; i++) {
      const x = list[i];
      let names = inputs(['name']);
      if (!names[i] && i > 0) {
        clickText(['add devotee', 'add pilgrim', 'add member', 'add more devotee'], false);
        await sleep(900);
        names = inputs(['name']);
      }
      if (!names[i]) {
        if (i === 0) return { n: -1, fails };
        fails.push('devotee ' + (i + 1) + ' form');
        continue;
      }
      const tag = list.length > 1 ? ' ' + (i + 1) : '';
      if (await fillAny(['name'], x.name, i)) n++;
      else fails.push('name' + tag);
      if (!(await fillAny(['age'], x.age, i))) fails.push('age' + tag);
      const g = await fillDropdown(['gender', 'sex'], x.gender, i);
      if (!g.ok) fails.push('gender' + tag + ' (' + g.why + ')');
      const p = await fillDropdown(['photo id proof', 'id proof', 'id type'], x.idType, i);
      if (!p.ok) fails.push('ID proof' + tag + ' (' + p.why + ')');
      await sleep(600);
      if (!(await fillAny(['photo id number', 'id number', 'id no'], x.idNumber, i)))
        fails.push('ID number' + tag);
    }
    return { n, fails };
  }

  async function fillGeneral(g) {
    let n = 0;
    const fails = [];
    const items = [
      ['email', ['email', 'email id', 'mail id'], g.email],
      ['city', ['city'], g.city],
      ['state', ['state'], g.state],
      ['country', ['country'], g.country],
      ['pincode', ['pincode', 'pin code', 'zip', 'postal code'], g.pincode],
    ];
    for (const it of items) {
      if (await fillAny(it[1], it[2], 0)) n++;
      else fails.push(it[0]);
      await sleep(250);
    }
    return { n, fails };
  }

  // ---------- login icon ----------
  const LOGIN_RE = /log[-_ ]?in|sign[-_ ]?in|exit_to_app/i;
  const LOGOUT_RE = /log[-_ ]?out|sign[-_ ]?out|power/i;

  // The element must really be on screen and on top (not hidden, off-screen or covered).
  function hitOk(e) {
    if (!document.elementFromPoint) return true;
    const r = e.getBoundingClientRect();
    const cx = r.left + r.width / 2;
    const cy = r.top + r.height / 2;
    if (cx < 0 || cy < 0 || cx > window.innerWidth || cy > window.innerHeight) return false;
    const h = document.elementFromPoint(cx, cy);
    return !!h && (h === e || e.contains(h));
  }
  const smallNoText = (e, min, max) => {
    const r = e.getBoundingClientRect();
    return (
      r.width >= min && r.width <= max && r.height >= min && r.height <= max &&
      (e.innerText || '').trim().length <= 20
    );
  };
  const clickableOf = (e) => e.closest('button,a,[role=button]') || e;

  const LOGIN_ATTR =
    '[class*="login" i],[id*="login" i],[aria-label*="login" i],[title*="login" i],' +
    '[alt*="login" i],[src*="login" i],[class*="signin" i],[aria-label*="sign in" i]';

  let lastIconInfo = '';
  function headerIcon() {
    // 1) elements that say "login" in their class, id, title or image name
    const byAttr = [...document.querySelectorAll(LOGIN_ATTR)].filter(
      (e) => vis(e) && smallNoText(e, 16, 100) && hitOk(e)
    );
    if (byAttr.length) {
      lastIconInfo = 'by name';
      return clickableOf(byAttr[0]);
    }
    // 2) the right-most small icon near the top of the page
    const W = window.innerWidth;
    const c = [
      ...document.querySelectorAll('button,a,[role=button],mat-icon,i,svg,img,span,div'),
    ].filter((e) => {
      if (!vis(e) || !smallNoText(e, 18, 90)) return false;
      const r = e.getBoundingClientRect();
      return r.left > W * 0.7 && r.top + (window.scrollY || 0) < 650 && hitOk(e);
    });
    lastIconInfo = c.length + ' icons near top right';
    if (!c.length) return null;
    c.sort((a, b) => {
      const ra = a.getBoundingClientRect();
      const rb = b.getBoundingClientRect();
      return rb.right - ra.right || rb.width * rb.height - ra.width * ra.height;
    });
    return clickableOf(c[0]);
  }

  // Like querySelectorAll, but also looks inside shadow roots.
  function deepAll(sel, root, out) {
    root = root || document;
    out = out || [];
    root.querySelectorAll(sel).forEach((e) => out.push(e));
    root.querySelectorAll('*').forEach((h) => {
      if (h.shadowRoot) deepAll(sel, h.shadowRoot, out);
    });
    return out;
  }
  function deepActive() {
    let a = document.activeElement;
    while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement;
    return a;
  }
  const isTextBox = (e) =>
    e && (e.tagName === 'INPUT' || e.tagName === 'TEXTAREA' || e.isContentEditable === true) &&
    !SKIP.includes(e.type);

  // The mobile number box, found by label, by type, or by where it sits above Get OTP.
  function phoneInput() {
    let el = inputs(PHONE)[0];
    if (el) return el;
    const all = deepAll('input,textarea').filter((e) => vis(e) && !SKIP.includes(e.type));
    el = all.find(
      (e) =>
        e.type === 'tel' ||
        /tel|numeric|decimal/i.test(e.getAttribute('inputmode') || '') ||
        /tel/i.test(e.getAttribute('autocomplete') || '')
    );
    if (el) return el;
    for (const e of all) {
      let c = e;
      for (let i = 0; i < 5 && c.parentElement; i++) {
        c = c.parentElement;
        const t = norm(c.innerText);
        if (t.length > 120) break;
        const n = [...c.querySelectorAll('input,textarea')].filter(
          (x) => vis(x) && !SKIP.includes(x.type)
        ).length;
        if (n === 1 && has(t, PHONE)) return e;
      }
    }
    const btn = getOtpButton();
    if (btn) {
      const br = btn.getBoundingClientRect();
      const cands = all
        .concat(deepAll('[contenteditable=true],[role=textbox]').filter(vis))
        .filter((e) => e.getBoundingClientRect().bottom <= br.top + 4)
        .sort((x, y) => y.getBoundingClientRect().bottom - x.getBoundingClientRect().bottom);
      if (cands.length) return cands[0];
    }
    if (all.length === 1) return all[0];
    return null;
  }
  // Last resort: tap where the number box should be and use whatever gets the focus.
  async function focusPhoneByTap() {
    const lab = findText(['registered mobile number', 'mobile number'], false);
    const pre = findText(['(+91)', '+91'], false);
    for (const t of [pre, lab]) {
      if (!t) continue;
      fireClick(t);
      await sleep(250);
      const a = deepActive();
      if (isTextBox(a)) return a;
    }
    return null;
  }
  function phoneDiag() {
    const ins = deepAll('input,textarea').map(
      (e) => e.tagName.toLowerCase() + '[' + (e.type || '') + (vis(e) ? '' : ',hidden') + ']'
    );
    const ce = deepAll('[contenteditable=true],[role=textbox]').length;
    const fr = document.querySelectorAll('iframe').length;
    const btn = getOtpButton();
    let near = '';
    if (btn) {
      let c = btn;
      for (let i = 0; i < 3 && c.parentElement; i++) c = c.parentElement;
      near = (c.outerHTML || '').replace(/\s+/g, ' ').slice(0, 260);
    }
    return 'inputs=' + (ins.join(',') || 'none') + ' editable=' + ce + ' iframes=' + fr + (near ? ' html=' + near : '');
  }
  function iconKind(el) {
    const h = (el.outerHTML || '').slice(0, 600);
    if (LOGOUT_RE.test(h)) return 'logout';
    if (LOGIN_RE.test(h)) return 'login';
    return 'unknown';
  }
  // The phone box of the login dialog. Falls back to "the input next to the Get OTP button"
  // because the site's label may not be a normal <label>.
  function getOtpButton() {
    const m = [...document.querySelectorAll('button,[role=button],a,div,span')].filter(
      (e) => vis(e) && norm(e.innerText) === 'get otp'
    );
    if (!m.length) return null;
    const inner = m[m.length - 1];
    return inner.closest('button,[role=button]') || inner;
  }
  const loginOpen = () => !!getOtpButton() || !!phoneInput();

  // Possible places to tap for the login icon, best guess first.
  function loginTargets() {
    const out = [];
    const add = (e) => {
      if (e && vis(e) && !out.includes(e)) out.push(e);
    };
    const hi = headerIcon();
    if (hi) {
      add(hi);
      const r = hi.getBoundingClientRect();
      add(document.elementFromPoint && document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2));
      add(hi.querySelector('svg,img,i,mat-icon'));
    }
    return out;
  }
  const descr = (e) =>
    e.tagName.toLowerCase() + (typeof e.className === 'string' && e.className ? '.' + e.className.split(' ')[0] : '');

  function otpVisible() {
    return [...document.querySelectorAll('input,button,label,span,div,p,h1,h2,h3')].some((e) => {
      if (!vis(e)) return false;
      const t = e.tagName === 'INPUT' ? labelOf(e) : e.innerText;
      const n = norm(t);
      return n && n.length < 80 && (' ' + n + ' ').includes(' otp ');
    });
  }

  // ---------- calendar ----------
  const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
  const MONTH_RE = new RegExp('^(' + MONTHS.join('|') + ')\\s+\\d{4}$', 'i');

  function calHeader() {
    return [...document.querySelectorAll('div,span,h1,h2,h3,h4,h5,p,th,button')].find(
      (e) => vis(e) && MONTH_RE.test((e.innerText || '').trim())
    );
  }

  async function gotoMonth(year, month0) {
    for (let k = 0; k < 14; k++) {
      const h = calHeader();
      if (!h) return true;
      const parts = h.innerText.trim().toLowerCase().split(/\s+/);
      const diff = (year - parseInt(parts[1], 10)) * 12 + (month0 - MONTHS.indexOf(parts[0]));
      if (diff === 0) return true;
      const hr = h.getBoundingClientRect();
      const W = window.innerWidth;
      const arrows = [
        ...document.querySelectorAll('button,[role=button],a,mat-icon,i,svg,img,span,div'),
      ].filter((e) => {
        if (!vis(e)) return false;
        const r = e.getBoundingClientRect();
        const sideOk = diff > 0 ? r.left > W * 0.7 : r.right < W * 0.3;
        return (
          r.width >= 18 && r.width <= 80 && r.height >= 18 && r.height <= 80 &&
          r.top > hr.top && r.top < hr.bottom + 520 && sideOk &&
          (e.innerText || '').trim().length <= 16
        );
      });
      if (!arrows.length) return false;
      arrows.sort((a, b) => {
        const ra = a.getBoundingClientRect();
        const rb = b.getBoundingClientRect();
        return rb.width * rb.height - ra.width * ra.height;
      });
      fireClick(arrows[0].closest('button,[role=button],a') || arrows[0]);
      await sleep(650);
    }
    return false;
  }

  function bgOf(el) {
    let e = el;
    for (let i = 0; i < 5 && e; i++) {
      const c = getComputedStyle(e).backgroundColor || '';
      const m = c.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
      if (m && (m[4] === undefined || parseFloat(m[4]) > 0.2)) return [+m[1], +m[2], +m[3]];
      e = e.parentElement;
    }
    return null;
  }
  function dateState(rgb) {
    if (!rgb) return 'ok';
    const r = rgb[0], g = rgb[1], b = rgb[2];
    if (r > 110 && g < 80 && b < 80) return 'full';
    if (Math.abs(r - g) < 14 && Math.abs(g - b) < 14 && r > 170 && r < 236) return 'na';
    if (b > r + 30 && g > 140 && b > g) return 'notreleased'; // light blue, not the purple "selected" cell
    return 'ok';
  }

''';
