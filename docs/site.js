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

  // Hovering the sample result runs the scan again
  var result = document.getElementById('result');
  result.addEventListener('mouseenter', function () {
    result.classList.remove('run'); void result.offsetWidth; result.classList.add('run');
  });
})();
