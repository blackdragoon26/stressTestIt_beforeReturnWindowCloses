(function () {
  // Operating system switch, preselected from the visitor's own system
  var tabs = Array.prototype.slice.call(document.querySelectorAll('.os [role="tab"]'));
  function pick(id) {
    tabs.forEach(function (t) {
      var on = t.id === 'tab-' + id;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      document.getElementById(t.getAttribute('aria-controls')).hidden = !on;
    });
  }
  tabs.forEach(function (t) { t.addEventListener('click', function () { pick(t.id.slice(4)); }); });
  var ua = navigator.userAgent;
  if (/Macintosh|Mac OS X/.test(ua) && !/iPhone|iPad/.test(ua)) pick('mac');
  else if (/Linux|X11/.test(ua) && !/Android/.test(ua)) pick('linux');

  // Copy buttons: the clipboard when allowed, otherwise select the text
  document.querySelectorAll('.copy').forEach(function (b) {
    b.addEventListener('click', function () {
      var code = b.closest('.code').querySelector('code');
      function done() { b.textContent = 'Copied'; setTimeout(function () { b.textContent = 'Copy'; }, 1500); }
      function selectInstead() {
        var r = document.createRange(); r.selectNodeContents(code);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
        b.textContent = 'Press Ctrl+C';
      }
      try { navigator.clipboard.writeText(code.innerText).then(done, selectInstead); } catch (e) { selectInstead(); }
    });
  });

  // Headline: types each question, holds it, erases it, then the next one. Screen readers get one
  // fixed question (#rotor-static). With reduced motion the first question simply stays.
  var typed = document.getElementById('typed');
  var caret = typed && typed.nextElementSibling;
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (typed && !reduce) {
    var lines = Array.prototype.map.call(document.querySelectorAll('.ghosts > span'), function (el) { return el.textContent; });
    var i = 0, n = lines[0].length, deleting = false;
    function step() {
      var line = lines[i], wait;
      if (!deleting && n < line.length) { n++; wait = 26 + Math.random() * 24; }
      else if (!deleting) { deleting = true; wait = 1400; }
      else if (n > 0) { n--; wait = 12; }
      else { deleting = false; i = (i + 1) % lines.length; wait = 220; }
      typed.textContent = line.slice(0, n);
      // the caret holds still while typing and blinks while it waits
      caret.classList.toggle('typing', wait < 250);
      setTimeout(step, wait);
    }
    setTimeout(function () { deleting = true; step(); }, 1400);
  }

  // What it checks: reads docs/checks.md (the same list the docs show) and cycles through it a few
  // checks at a time. Each set arrives under a scan line that sweeps down the box, every result stamping
  // in as the line passes; a thin bar fills while it holds, then the next set comes. Hover pauses it,
  // a click moves on.
  var live = document.querySelector('.checks-live');
  var box = document.getElementById('checks');
  if (live && box && window.fetch) {
    var esc = function (t) { return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); };
    var inline = function (t) {
      return esc(t).replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/\*\*([^*]+)\*\*/g, '$1').replace(/\*([^*]+)\*/g, '<em>$1</em>');
    };
    var levels = ['FAIL', 'WARN', 'PASS', 'INFO'];   // the strongest first
    fetch('checks.md').then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); }).then(function (md) {
      var topics = [], cur = null;
      md.split('\n').forEach(function (line) {
        var h = /^## (.+)$/.exec(line);
        if (h) { cur = { title: h[1].replace(/`/g, ''), head: null, rows: [] }; topics.push(cur); return; }
        if (!cur || line.charAt(0) !== '|' || /^[|\s:-]+$/.test(line)) return;
        var cells = line.replace(/^\|/, '').replace(/\|\s*$/, '').split('|').map(function (c) { return c.trim(); });
        if (!cur.head) cur.head = cells; else cur.rows.push(cells);
      });
      // Only the tables with a Result column (the Windows checks and the hands-on tests)
      var frames = [], total = 0, per = 4;
      topics.forEach(function (t) {
        if (!t.head || t.head[t.head.length - 1] !== 'Result') return;
        total += t.rows.length;
        // Even sets: 5 checks become 3 + 2, 11 become 4 + 4 + 3
        var parts = Math.ceil(t.rows.length / per), size = Math.ceil(t.rows.length / parts);
        for (var k = 0; k < parts; k++) frames.push({ t: t, part: k + 1, parts: parts, rows: t.rows.slice(k * size, k * size + size) });
      });
      if (!frames.length) return;
      document.getElementById('checks-total').textContent = total;
      live.hidden = false;
      var topic = box.querySelector('.topic'), count = box.querySelector('.frame'), rows = box.querySelector('.rows');
      var at = -1;
      function row(cells) {
        var verdict = cells[cells.length - 1].replace(/^\s*\*spec\*:\s*/, '');
        // The tag carries the level. A verdict that starts with it loses the word ("FAIL if they differ" ->
        // "if they differ"); a mixed one ("resolution FAIL, refresh WARN") stays whole, tagged by its first level
        var lead = /^(FAIL|WARN|PASS|INFO)\b[\s:,.]*/.exec(verdict), lvl = 'INFO', rest = verdict;
        if (lead) { lvl = lead[1]; rest = verdict.slice(lead[0].length); }
        else levels.some(function (l) { if (verdict.indexOf(l) >= 0) { lvl = l; return true; } return false; });
        rest = rest.replace(/^\((.*)\)$/, '$1');
        rest = inline(rest).replace(/\b(FAIL|WARN|PASS|INFO)\b/g, '<b>$1</b>');
        return '<div class="row"><span class="tag ' + lvl.toLowerCase() + '">' + lvl + '</span><span class="row-text"><span class="row-name">' +
          inline(cells[0]) + '</span>' + (rest ? '<span class="row-rest">' + rest + '</span>' : '') + '</span></div>';
      }
      function show(k) {
        at = (k + frames.length) % frames.length;
        var f = frames[at];
        topic.textContent = f.t.title + (f.parts > 1 ? ' (' + f.part + ' of ' + f.parts + ')' : '');
        count.textContent = (at + 1) + ' / ' + frames.length;
        rows.innerHTML = f.rows.map(row).join('');
        box.classList.remove('run'); void box.offsetWidth; box.classList.add('run');
      }
      function next() {
        if (reduce) { show(at + 1); return; }
        box.classList.add('leave');
        setTimeout(function () { box.classList.remove('leave'); show(at + 1); }, 280);
      }
      // The bar's fill animation is the clock: when it ends, the next set comes; hovering pauses it
      box.querySelector('.bar').addEventListener('animationend', next);
      box.addEventListener('click', next);
      show(0);
    }).catch(function () { /* no list, no box: the docs still have every check */ });
  }
})();
