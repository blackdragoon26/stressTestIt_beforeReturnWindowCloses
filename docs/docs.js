(function () {
  // The pages are the Markdown files next to this one: the same files GitHub shows in docs/.
  var pages = ['guide', 'checks', 'profiles', 'trust', 'omen-day'];
  var doc = document.getElementById('doc');
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function copyText(button, text) {
    function done() { button.textContent = 'Copied'; setTimeout(function () { button.textContent = 'Copy'; }, 1500); }
    function selectInstead() {
      var r = document.createRange();
      r.selectNodeContents(button.closest('.code').querySelector('code'));
      var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
      button.textContent = 'Press Ctrl+C';
    }
    try { navigator.clipboard.writeText(text).then(done, selectInstead); } catch (e) { selectInstead(); }
  }

  // Addresses are docs.html#<page> or docs.html#<page>/<section>, for example #guide/clean-up
  var current = null;
  function slug(t) { return t.toLowerCase().trim().replace(/[^\w\s-]/g, '').replace(/\s+/g, '-'); }

  // ---------- the guide: ask which system, then show only that one ----------
  // The page's Windows, Linux and macOS sections become panels. With no choice saved yet, the page asks;
  // after that a bar switches between the three, or "Full guide" shows the whole document.
  var systems = { windows: 'Windows', linux: 'Linux', macos: 'macOS' };
  function savedOs() { try { return localStorage.getItem('st-os'); } catch (e) { return null; } }
  function saveOs(id) { try { localStorage.setItem('st-os', id); } catch (e) { } }
  function guessOs() {
    var ua = navigator.userAgent;
    if (/Macintosh|Mac OS X/.test(ua) && !/iPhone|iPad/.test(ua)) return 'macos';
    if (/Linux|X11/.test(ua) && !/Android/.test(ua)) return 'linux';
    return 'windows';
  }
  function replay(el, cls) { if (reduce) return; el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); }
  function pickOs(id, animate) {
    var g = doc.querySelector('.osg');
    if (!g) return;
    var ask = g.querySelector('.os-ask'), bar = g.querySelector('.os');
    ask.hidden = !!id; bar.hidden = !id;
    bar.querySelectorAll('button').forEach(function (b) {
      var on = b.getAttribute('data-os') === id;
      b.setAttribute('aria-selected', on ? 'true' : 'false');
      b.tabIndex = on ? 0 : -1;
    });
    doc.classList.toggle('full', id === 'all');
    doc.querySelectorAll('.os-panel').forEach(function (p) {
      var on = id === 'all' || p.id === 'os-' + id;
      p.hidden = !on;
      if (on && animate) replay(p, 'enter');
    });
    if (animate && id) replay(bar, 'enter');
  }
  function osGuide() {
    var heads = Array.prototype.filter.call(doc.querySelectorAll('h2'), function (h) { return systems[slug(h.textContent)]; });
    if (heads.length < 2) return;
    var g = document.createElement('div'); g.className = 'osg';
    heads[0].parentNode.insertBefore(g, heads[0]);
    var ask = document.createElement('div'); ask.className = 'os-ask';
    ask.innerHTML = '<p class="os-q">Which system are you checking?</p><div class="os-cards"></div>' +
      '<button type="button" class="os-all" data-os="all">Or read the full guide</button>';
    var bar = document.createElement('div');
    bar.className = 'os'; bar.setAttribute('role', 'tablist'); bar.setAttribute('aria-label', 'Operating system');
    g.appendChild(ask); g.appendChild(bar);
    var guess = guessOs();
    heads.forEach(function (h, k) {
      var id = slug(h.textContent);
      var panel = document.createElement('section');
      panel.className = 'os-panel'; panel.id = 'os-' + id; panel.setAttribute('role', 'tabpanel');
      var n = h.nextSibling;
      h.parentNode.replaceChild(panel, h);
      panel.appendChild(h);   // the heading stays, shown only in the full guide
      while (n && !(n.nodeType === 1 && n.tagName === 'H2')) { var next = n.nextSibling; panel.appendChild(n); n = next; }
      // A card for the question, its note taken from the section's first line
      var first = panel.querySelector('p');
      var card = document.createElement('button');
      card.type = 'button'; card.className = 'os-card' + (id === guess ? ' guess' : ''); card.setAttribute('data-os', id);
      card.innerHTML = '<span class="os-name"></span><span class="os-note"></span>' + (id === guess ? '<span class="os-hint">Your system</span>' : '');
      card.querySelector('.os-name').textContent = systems[id];
      card.querySelector('.os-note').textContent = first ? first.textContent : '';
      ask.querySelector('.os-cards').appendChild(card);
      var b = document.createElement('button');
      b.type = 'button'; b.setAttribute('role', 'tab'); b.setAttribute('data-os', id); b.textContent = systems[id];
      bar.appendChild(b);
    });
    var all = document.createElement('button');
    all.type = 'button'; all.setAttribute('role', 'tab'); all.setAttribute('data-os', 'all'); all.textContent = 'Full guide';
    bar.appendChild(all);
    g.addEventListener('click', function (e) {
      var b = e.target.closest('[data-os]');
      if (!b) return;
      var id = b.getAttribute('data-os');
      saveOs(id); pickOs(id, true);
      g.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
    });
    var want = savedOs();
    pickOs(systems[want] || want === 'all' ? want : null, false);
  }

  // ---------- the checks: a guided tour, one topic at a time ----------
  // Each h2 becomes a slide; each table row becomes one line (the check and its verdict) that opens to
  // show what it reads. Pills and arrows move between topics; "All" shows every topic on one page.
  var tourGo = null;
  function short(t) {
    var map = { 'which-checks-run-in-each-mode': 'Modes', 'every-report-also-contains': 'Every report' };
    return map[slug(t)] || t.split(/[:(]/)[0].trim();
  }
  function tag(html) { return html.replace(/\b(FAIL|WARN|PASS|INFO)\b/g, '<span class="t t-$1">$1</span>'); }
  function tour() {
    var heads = Array.prototype.slice.call(doc.querySelectorAll('h2'));
    if (!heads.length) return;
    var box = document.createElement('div'); box.className = 'tour';
    box.innerHTML = '<div class="tour-nav" role="tablist" aria-label="Topics"></div><div class="tour-stage"></div>' +
      '<div class="tour-foot"><button type="button" class="tour-prev" aria-label="Previous topic">&larr;</button>' +
      '<span class="tour-count"></span><button type="button" class="tour-next" aria-label="Next topic">Next &rarr;</button></div>';
    heads[0].parentNode.insertBefore(box, heads[0]);
    var nav = box.querySelector('.tour-nav'), stage = box.querySelector('.tour-stage');
    var slides = heads.map(function (h, k) {
      var s = document.createElement('section'); s.className = 'slide'; s.id = h.id; s.hidden = true;
      var title = document.createElement('h2'); title.className = 'slide-title'; title.innerHTML = h.innerHTML;
      s.appendChild(title);
      var n = h.nextSibling, count = 0;
      while (n && !(n.nodeType === 1 && n.tagName === 'H2')) {
        var next = n.nextSibling;
        var table = n.nodeType === 1 && (n.tagName === 'TABLE' ? n : n.querySelector && n.querySelector('table'));
        if (table) {
          var heads2 = Array.prototype.map.call(table.querySelectorAll('thead th'), function (th) { return th.textContent; });
          var list = document.createElement('ol'); list.className = 'items';
          table.querySelectorAll('tbody tr').forEach(function (tr, i) {
            var c = tr.children, last = c.length - 1;
            var li = document.createElement('li'); li.className = 'item'; li.style.setProperty('--i', i);
            var more = '';
            for (var j = 1; j < last; j++) more += '<p><span class="lbl">' + heads2[j] + '</span>' + c[j].innerHTML + '</p>';
            var headTag = more ? 'button' : 'div';
            li.innerHTML = '<' + headTag + (more ? ' type="button" aria-expanded="false"' : '') + ' class="item-head">' +
              '<span class="item-name">' + c[0].innerHTML + '</span><span class="item-verdict">' + tag(c[last].innerHTML) + '</span>' +
              (more ? '<span class="item-plus" aria-hidden="true"></span>' : '') + '</' + headTag + '>' +
              (more ? '<div class="item-more"><div>' + more + '</div></div>' : '');
            list.appendChild(li); count++;
          });
          s.appendChild(list);
          n.parentNode.removeChild(n);
        } else { s.appendChild(n); }
        n = next;
      }
      if (count) { var m = document.createElement('span'); m.className = 'slide-count'; m.textContent = count + (count === 1 ? ' check' : ' checks'); title.appendChild(m); }
      h.parentNode.removeChild(h);
      stage.appendChild(s);
      var pill = document.createElement('button');
      pill.type = 'button'; pill.setAttribute('role', 'tab'); pill.textContent = short(h.textContent);
      pill.addEventListener('click', function () { go(k); });
      nav.appendChild(pill);
      return s;
    });
    var allPill = document.createElement('button');
    allPill.type = 'button'; allPill.setAttribute('role', 'tab'); allPill.className = 'pill-all'; allPill.textContent = 'All';
    nav.appendChild(allPill);
    var at = -1;
    function go(k, quiet) {
      if (k === 'all') {
        at = -1; box.classList.add('all');
        slides.forEach(function (s) { s.hidden = false; s.classList.remove('in-next', 'in-prev'); });
      } else {
        k = (k + slides.length) % slides.length;
        var dir = k >= at ? 'in-next' : 'in-prev';
        box.classList.remove('all');
        slides.forEach(function (s, i) { s.hidden = i !== k; });
        if (!quiet) { slides[k].classList.remove('in-next', 'in-prev'); replay(slides[k], dir); }
        at = k;
        box.querySelector('.tour-count').textContent = (k + 1) + ' / ' + slides.length;
        box.querySelector('.tour-next').innerHTML = k === slides.length - 1 ? 'Start again &rarr;' : 'Next &rarr;';
      }
      nav.querySelectorAll('button').forEach(function (b, i) {
        var on = k === 'all' ? b === allPill : i === at;
        b.setAttribute('aria-selected', on ? 'true' : 'false');
      });
    }
    allPill.addEventListener('click', function () { go('all'); });
    box.querySelector('.tour-prev').addEventListener('click', function () { go(at - 1); });
    box.querySelector('.tour-next').addEventListener('click', function () { go(at + 1); });
    stage.addEventListener('click', function (e) {
      var h = e.target.closest('button.item-head');
      if (!h) return;
      var li = h.parentNode, open = !li.classList.contains('open');
      li.classList.toggle('open', open); h.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    document.addEventListener('keydown', function (e) {
      if (!document.body.contains(box) || at < 0 || /INPUT|TEXTAREA/.test(e.target.tagName)) return;
      if (e.key === 'ArrowRight') go(at + 1); else if (e.key === 'ArrowLeft') go(at - 1);
    });
    tourGo = function (id) { for (var i = 0; i < slides.length; i++) if (slides[i].id === id) { go(i); return true; } return false; };
    go(0, true);
  }

  // Go to a section. A section inside a hidden system tab is looked up in the tab that is showing
  // ("#guide/clean-up" lands on the Clean up of your system), and a closed section is opened.
  function toSection(sec) {
    var el = sec && document.getElementById(sec);
    if (el && el.closest('.os-panel[hidden]')) {
      var base = el.getAttribute('data-base');
      var shown = doc.querySelector('.os-panel:not([hidden])');
      var twin = shown && shown.querySelector('[data-base="' + base + '"]');
      if (twin) el = twin;
    }
    if (el && el.classList.contains('slide') && tourGo) tourGo(el.id);
    if (el) el.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth' }); else window.scrollTo(0, 0);
  }

  function show() {
    var parts = (location.hash || '#guide').slice(1).split('/');
    var p = parts[0], sec = parts[1] || '';
    if (pages.indexOf(p) < 0) p = 'guide';
    if ((systems[sec] || sec === 'all') && p === current) { saveOs(sec); pickOs(sec, true); window.scrollTo(0, 0); return; }
    if (p === current) { toSection(sec); return; }   // same page: only move to the section
    current = p;
    document.querySelectorAll('nav a').forEach(function (a) {
      if (a.getAttribute('href') === 'docs.html#' + p) a.setAttribute('aria-current', 'page');
      else a.removeAttribute('aria-current');
    });
    doc.innerHTML = '<p class="status">Loading...</p>';

    fetch(p + '.md')
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (md) {
        doc.innerHTML = marked.parse(md);
        doc.classList.remove('in'); void doc.offsetWidth; doc.classList.add('in');   // gentle rise on every page
        var h1 = doc.querySelector('h1');
        if (h1) document.title = h1.textContent + ' - SecondTrust';

        // Every heading gets the id GitHub gives it (repeats get -1, -2), so section links work on both
        var seen = {};
        doc.querySelectorAll('h1, h2, h3').forEach(function (h) {
          var base = slug(h.textContent);
          h.id = seen[base] ? base + '-' + seen[base] : base;
          seen[base] = (seen[base] || 0) + 1;
          h.setAttribute('data-base', base);
        });

        // Links between pages: "checks.md" becomes "docs.html#checks", "guide.md#clean-up" becomes
        // "docs.html#guide/clean-up", and "#clean-up" on this page becomes "docs.html#<page>/clean-up"
        doc.querySelectorAll('a[href]').forEach(function (a) {
          var href = a.getAttribute('href');
          var m = href.match(/^([a-z-]+)\.md(?:#([\w-]+))?$/);
          if (m && pages.indexOf(m[1]) >= 0) a.setAttribute('href', 'docs.html#' + m[1] + (m[2] ? '/' + m[2] : ''));
          else if (/^#[\w-]+$/.test(href)) a.setAttribute('href', 'docs.html#' + p + '/' + href.slice(1));
          if (/^https?:/.test(a.getAttribute('href'))) a.setAttribute('rel', 'noopener');
        });

        // Wide tables scroll sideways on phones instead of widening the page
        doc.querySelectorAll('table').forEach(function (t) {
          var w = document.createElement('div');
          w.className = 'scroll';
          t.parentNode.insertBefore(w, t);
          w.appendChild(t);
        });

        // Every code block gets a label bar with a copy button above it, so the button never covers text
        doc.querySelectorAll('pre').forEach(function (pre) {
          var code = pre.querySelector('code');
          var lang = ((code && code.className) || '').replace('language-', '');
          var names = { powershell: 'PowerShell', bash: 'Terminal', sh: 'Terminal' };
          var box = document.createElement('div'); box.className = 'code';
          var bar = document.createElement('div'); bar.className = 'code-bar';
          var label = document.createElement('span'); label.textContent = names[lang] || lang || 'Text';
          var b = document.createElement('button'); b.className = 'copy'; b.type = 'button'; b.textContent = 'Copy';
          b.addEventListener('click', function () { copyText(b, code.innerText); });
          bar.appendChild(label); bar.appendChild(b);
          pre.parentNode.insertBefore(box, pre);
          box.appendChild(bar); box.appendChild(pre);
        });

        tourGo = null;
        if (p === 'guide') osGuide();
        if (p === 'checks') tour();
        if (systems[sec] || sec === 'all') { saveOs(sec); pickOs(sec, false); sec = ''; }
        toSection(sec);
      })
      .catch(function () {
        current = null;
        doc.innerHTML = '<p class="status">This page could not be loaded. Read it on GitHub: ' +
          '<a href="https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/tree/main/docs">docs/</a></p>';
      });
  }

  window.addEventListener('hashchange', show);
  show();
})();
