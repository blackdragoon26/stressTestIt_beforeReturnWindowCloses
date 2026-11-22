// The live background on every page: a faint dot grid with a slow, soft wave of light passing through it,
// and a glow that follows the pointer. Drawn at 30 frames a second at most (browsers pause it in hidden
// tabs); a still frame with reduced motion.
(function () {
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var cv = document.getElementById('bg');
  if (cv && cv.getContext) {
    var ctx = cv.getContext('2d'), W = 0, H = 0, dpr = 1, ink = '10,10,10';
    // data-strength on the canvas: 1 on the landing page, fainter behind the docs so text stays easy to read
    var strength = (parseFloat(cv.getAttribute('data-strength')) || 1) * 1.25;
    // Scrolling lights the grid up a little (glow, 0 to 1), which fades out about a second after you stop;
    // the waves also drift with the page, so the background follows the movement
    var glow = 0, lastScroll = window.scrollY || 0, drift = 0;
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
      var t = (now - t0) / 1000 + drift;
      var lift = strength * (1 + 0.9 * glow);
      ctx.clearRect(0, 0, W, H);
      for (var y = gap / 2; y < H; y += gap) {
        for (var x = gap / 2; x < W; x += gap) {
          // two slow waves crossing: bright where both peak, so the light stays sparse
          var w1 = 0.5 + 0.5 * Math.sin(x * 0.006 + y * 0.004 - t * 0.55);
          var w2 = 0.5 + 0.5 * Math.sin(x * -0.003 + y * 0.007 - t * 0.31 + 1.7);
          var a = (0.05 + 0.16 * Math.pow(w1 * w2, 2)) * lift;
          var s = 1.6;
          var dx = x - mx, dy = y - my, d2 = dx * dx + dy * dy;
          if (d2 < 19600) { var k = 1 - Math.sqrt(d2) / 140; a += 0.22 * k * lift; s += 1.2 * k; }
          ctx.fillStyle = 'rgba(' + ink + ',' + a.toFixed(3) + ')';
          ctx.fillRect(x - s / 2, y - s / 2, s, s);
        }
      }
    }
    function loop(now) {
      if (now - last > 33) { glow *= 0.94; last = now; draw(now); }
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
      window.addEventListener('scroll', function () {
        var y = window.scrollY || 0, d = Math.abs(y - lastScroll);
        lastScroll = y;
        glow = Math.min(1, glow + d / 400);
        drift = y * 0.0025;
      }, { passive: true });
      document.addEventListener('pointerleave', function () { mx = my = -1e4; });
      requestAnimationFrame(loop);
    }
  }
})();
