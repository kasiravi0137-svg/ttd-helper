// Page script, part 2: the step functions (login, phone, date, slot, devotees...).
import 'page_script_helpers.dart';

const kJsSteps = r'''
  // ---------- public API ----------
  window.__ttd = {
    v: 4,
    state,

    openLogin() {
      return run(async () => {
        if (loginOpen()) return done(true, 'Login box is open');
        window.scrollTo(0, 0);
        await sleep(300);
        if (present(['login', 'log in', 'sign in']) && clickText(['login', 'log in', 'sign in'], true)) {
          await sleep(1000);
          if (loginOpen()) return done(true, 'Opened login');
        }
        const t = loginTargets();
        if (!t.length) return done(false, 'Login icon not found (' + lastIconInfo + ')');
        if (iconKind(t[0]) === 'logout') return done(true, 'Already signed in', { skip: true });
        state.iconClicks++;
        const tried = [];
        for (const el of t.slice(0, 4)) {
          if (iconKind(el) === 'logout') continue;
          tried.push(descr(el));
          fireClick(el);
          await sleep(1000);
          if (loginOpen()) return done(true, 'Opened login');
        }
        done(false, 'Tapped ' + tried.join(', ') + ' but no login box appeared.');
      });
    },

    // Gets the phone box ready (focused, old digits cleared) before the app types into it.
    prepPhone(p) {
      return run(async () => {
        let el = phoneInput();
        if (!el && getOtpButton()) el = await focusPhoneByTap();
        if (!el) return done(false, 'Waiting for the phone box...');
        el.scrollIntoView({ block: 'center' });
        el.focus();
        try {
          el.click();
        } catch (e) {}
        await sleep(250);
        const val = el.value || '';
        const prefix = (val.match(/^\D*91\D*/) || [''])[0];
        let d = digits(val);
        if (/\(\s*\+?\s*91|\+\s*91/.test(val)) d = d.slice(2);
        if (d === p) return done(true, 'typed', { typed: true });
        if (d.length) {
          try {
            el.setSelectionRange(prefix.length, val.length);
            document.execCommand('delete');
          } catch (e) {}
          await sleep(300);
        }
        try {
          el.setSelectionRange(el.value.length, el.value.length);
        } catch (e) {}
        done(true, 'ready', { ready: true });
      });
    },

    fillPhone(p) {
      return run(async () => {
        let el = phoneInput();
        if (!el && getOtpButton()) el = await focusPhoneByTap();
        if (!el) {
          return done(
            false,
            getOtpButton() ? 'Phone box not found. ' + phoneDiag() : 'Waiting for the phone box...'
          );
        }
        // Typing only works while the page really has focus (a real tap gives it).
        let have = digits(el.value || '');
        if (/\(\s*\+?\s*91|\+\s*91/.test(el.value || '')) have = have.slice(2);
        if (have !== p && !document.hasFocus() && (state.tapTries || 0) < 1) {
          state.tapTries = (state.tapTries || 0) + 1;
          const rc = el.getBoundingClientRect();
          return done(false, 'Tap the phone box once and I will fill the number', {
            needTap: true,
            x: rc.left + rc.width * 0.6,
            y: rc.top + rc.height / 2,
            iw: window.innerWidth,
          });
        }
        if (el.isContentEditable && el.tagName !== 'INPUT') {
          el.focus();
          try {
            document.execCommand('selectAll');
            document.execCommand('insertText', false, p);
          } catch (e) {}
        }
        let ok;
        let how = '';
        if (el.isContentEditable && el.tagName !== 'INPUT') {
          ok = digits(el.innerText).endsWith(p);
        } else {
          const r = await typePhone(el, p);
          ok = r.ok;
          how = r.how;
        }
        await sleep(700);
        if (!ok) return done(false, 'Could not type the number (box shows "' + (el.value || '') + '") ' + how);
        let btn = getOtpButton();
        if (btn && isDisabled(btn)) {
          // The page may only trust real key events: type the number again key by key.
          await sleep(800);
          btn = getOtpButton();
        }
        if (!btn) return done(true, 'Phone filled, tap Get OTP');
        if (isDisabled(btn)) return done(false, 'Number typed but Get OTP is still disabled');
        fireClick(btn);
        await sleep(1000);
        done(true, 'Phone filled, OTP requested');
      });
    },

    loggedIn() {
      return run(async () => {
        const dlg = inputs(['otp', 'enter otp']);
        if (dlg.length || phoneInput() || otpVisible()) {
          state.sawDialog = true;
          state.gone = 0;
          return done(false, '');
        }
        const ic = headerIcon();
        if (ic && iconKind(ic) === 'logout') return done(true, 'Signed in');
        if (state.sawDialog) {
          state.gone++;
          if (state.gone >= 2) return done(true, 'Signed in');
        }
        done(false, '');
      });
    },

    click(texts, exact) {
      return run(async () => {
        if (clickText(texts, !!exact)) {
          await sleep(900);
          done(true, 'Opened ' + texts[0]);
        } else {
          done(false, 'Waiting for "' + texts[0] + '"...');
        }
      });
    },

    pickDate(a) {
      return run(async () => {
        const ok = await gotoMonth(a.year, a.month - 1);
        if (!ok) return done(false, 'Could not reach that month on the calendar');
        const hdr = calHeader();
        const top = hdr ? hdr.getBoundingClientRect().bottom : 0;
        const day = String(a.day);
        let c = [
          ...document.querySelectorAll('td,button,a,div,span,li,[role=gridcell]'),
        ].filter((e) => {
          if (!vis(e)) return false;
          const r = e.getBoundingClientRect();
          return norm(e.innerText) === day && r.width <= 150 && r.height <= 150 && r.top >= top - 5 && r.top < top + 800;
        });
        c = c.filter((e) => !c.some((o) => o !== e && e.contains(o)));
        if (!c.length) return done(false, 'Waiting for day ' + day + ' on the calendar...');
        const cell = c[0];
        const st = dateState(bgOf(cell));
        if (st === 'full') return done(false, 'Quota is full on this date. Pick another date.');
        if (st === 'na') return done(false, 'Slots are not available on this date.');
        if (st === 'notreleased') return done(false, 'Quota is not released for this date yet.');
        fireClick(cell);
        await sleep(900);
        done(true, 'Date ' + day + ' selected');
      });
    },

    tickets(n) {
      return run(async () => {
        const want = String(n);
        const keys = ['number of tickets', 'no of tickets', 'tickets'];
        const s = selects(keys)[0];
        if (s && (await pickFrom(s, want))) return done(true, 'Tickets set to ' + want);
        const labs = labelEls(keys);
        if (!labs[0]) return done(false, 'Waiting for the tickets box...');
        const ctl = controlFor(labs[0]);
        const words = norm(ctl.innerText).split(' ');
        if (words[words.length - 1] === want) return done(true, 'Tickets already ' + want);
        const r = await openAndPick(ctl, want, true);
        done(r.ok, r.ok ? 'Tickets set to ' + want : 'Tickets: ' + r.why);
      });
    },

    slot(a) {
      return run(async () => {
        const all = [...document.querySelectorAll('div,span,p,label,li,mat-radio-button')].filter(
          (e) => vis(e) && (e.innerText || '').length < 90
        );
        let el = null;
        let used = '';
        for (const v of a.slots) {
          const w = ' ' + norm(v) + ' ';
          const c = all.filter((e) => (' ' + norm(e.innerText) + ' ').includes(w));
          const pref = c.filter((e) => norm(e.innerText).includes('slot time'));
          const pool = pref.length ? pref : c;
          if (pool.length) {
            el = pool.sort((x, y) => x.innerText.length - y.innerText.length)[0];
            used = v;
            break;
          }
        }
        if (!el) {
          const seen = all
            .map((e) => (e.innerText || '').trim())
            .filter((s) => /^slot time/i.test(s) && s.length < 30)
            .slice(0, 6)
            .join(' | ');
          return done(false, 'Slot ' + (a.slots[0] || '') + ' not found' + (seen ? ' (page shows: ' + seen + ')' : ''));
        }
        let card = el;
        let radio = null;
        for (let i = 0; i < 7 && card; i++) {
          radio = card.querySelector(
            'input[type=radio],mat-radio-button,[role=radio],.mat-radio-outer-circle,.mat-mdc-radio-button'
          );
          if (radio) break;
          card = card.parentElement;
        }
        if (!card) card = el;
        if (/\b(sold out|full|not available)\b/.test(norm(card.innerText)))
          return done(false, 'That slot is full. Pick another slot.');
        if (radio) {
          if (radio.tagName === 'INPUT') radio.click();
          else fireClick(radio);
        } else {
          fireClick(card);
        }
        await sleep(500);
        const inp = card.querySelector('input[type=radio]');
        if (inp && !inp.checked) {
          fireClick(card);
          await sleep(500);
          if (!inp.checked) return done(false, 'Could not tick the slot, tap it yourself');
        }
        done(true, 'Slot ' + used + ' selected');
      });
    },

    next() {
      return run(async () => {
        const onForm = () =>
          present(['pilgrim details']) || (inputs(['name']).length > 0 && inputs(['age']).length > 0);
        if (onForm()) return done(true, 'Pilgrim form is open');
        const btns = [...document.querySelectorAll('button,[role=button],a')].filter(
          (e) =>
            vis(e) &&
            !e.disabled &&
            e.getAttribute('aria-disabled') !== 'true' &&
            ['continue', 'proceed', 'next'].includes(norm(e.innerText))
        );
        if (!btns.length) return done(false, 'Waiting for the Continue button...');
        const b = btns[btns.length - 1];
        b.scrollIntoView({ block: 'center' });
        b.click();
        await sleep(1500);
        done(onForm(), 'Clicked Continue');
      });
    },

    devotees(a) {
      return run(async () => {
        const r = await fillDevotees(a.list);
        if (r.n < 0) return done(false, 'Waiting for the devotee form...');
        done(
          r.n > 0 && r.fails.length === 0,
          r.fails.length
            ? 'Not filled: ' + r.fails.join(', ') + '. Fill these yourself.'
            : 'Filled ' + r.n + ' of ' + a.list.length + ' devotees'
        );
      });
    },

    general(a) {
      return run(async () => {
        const r = await fillGeneral(a);
        done(
          r.n >= 3 && r.fails.length <= 1,
          r.fails.length ? 'Not filled: ' + r.fails.join(', ') : 'General details filled'
        );
      });
    },

    fillAll(a) {
      return run(async () => {
        const d = await fillDevotees(a.list);
        const g = await fillGeneral(a.general);
        const fails = d.fails.concat(g.fails);
        done(
          d.n > 0 || g.n > 0,
          fails.length
            ? 'Filled what I could. Not filled: ' + fails.join(', ')
            : 'Filled devotees and general details'
        );
      });
    },
  };
})();
''';

const kAutomationJs = kJsHelpers + kJsSteps;
