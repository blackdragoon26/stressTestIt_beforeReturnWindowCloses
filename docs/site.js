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

  // Background: a dot grid with a slow, soft wave of light passing through it, and a faint glow around the
  // pointer. Drawn at 30 frames a second at most, paused when the tab is hidden; a still frame with
  // reduced motion.
  var cv = document.getElementById('bg');
  if (cv && cv.getContext) {
    var ctx = cv.getContext('2d'), W = 0, H = 0, dpr = 1, ink = '10,10,10';
    var gap = 26, mx = -1e4, my = -1e4, last = 0, t0 = performance.now();
    function colour() {
      var fg = getComputedStyle(document.documentElement).getPropertyValue('--fg').trim();
      var m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(fg);
      ink = m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)].join(',') : '128,128,128';
    }
    function size() {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = window.innerWidth; H = window.innerHeight;
      cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      gap = W < 600 ? 22 : 26;
    }
    function draw(now) {
      var t = (now - t0) / 1000;
      ctx.clearRect(0, 0, W, H);
      for (var y = gap / 2; y < H; y += gap) {
        for (var x = gap / 2; x < W; x += gap) {
          // two slow waves crossing: bright where both peak, so the light stays sparse
          var w1 = 0.5 + 0.5 * Math.sin(x * 0.006 + y * 0.004 - t * 0.55);
          var w2 = 0.5 + 0.5 * Math.sin(x * -0.003 + y * 0.007 - t * 0.31 + 1.7);
          var a = 0.05 + 0.16 * Math.pow(w1 * w2, 2);
          var s = 1.6;
          var dx = x - mx, dy = y - my, d2 = dx * dx + dy * dy;
          if (d2 < 19600) { var k = 1 - Math.sqrt(d2) / 140; a += 0.22 * k; s += 1.2 * k; }
          ctx.fillStyle = 'rgba(' + ink + ',' + a.toFixed(3) + ')';
          ctx.fillRect(x - s / 2, y - s / 2, s, s);
        }
      }
    }
    function loop(now) {
      if (now - last > 33) { last = now; draw(now); }
      requestAnimationFrame(loop);
    }
    colour(); size();
    window.addEventListener('resize', function () { size(); if (reduce) draw(t0 + 4000); });
    if (window.matchMedia) {
      var dark = window.matchMedia('(prefers-color-scheme: dark)');
      var recolour = function () { colour(); if (reduce) draw(t0 + 4000); };
      if (dark.addEventListener) dark.addEventListener('change', recolour); else if (dark.addListener) dark.addListener(recolour);
    }
    if (reduce) { draw(t0 + 4000); }
    else {
      window.addEventListener('pointermove', function (e) { mx = e.clientX; my = e.clientY; }, { passive: true });
      document.addEventListener('pointerleave', function () { mx = my = -1e4; });
      requestAnimationFrame(loop);
    }
  }
})();
