(function () {
  // The pages are the Markdown files next to this one: the same files GitHub shows in docs/.
  var pages = ['guide', 'checks', 'profiles', 'trust', 'omen-day'];
  var doc = document.getElementById('doc');

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

  function show() {
    var p = (location.hash || '#guide').slice(1);
    if (pages.indexOf(p) < 0) p = 'guide';
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
        if (h1) document.title = h1.textContent + ' - DOA Kit';

        // Links between pages: "checks.md" becomes "docs.html#checks"
        doc.querySelectorAll('a[href]').forEach(function (a) {
          var m = a.getAttribute('href').match(/^([a-z-]+)\.md$/);
          if (m && pages.indexOf(m[1]) >= 0) a.setAttribute('href', 'docs.html#' + m[1]);
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
        window.scrollTo(0, 0);
      })
      .catch(function () {
        doc.innerHTML = '<p class="status">This page could not be loaded. Read it on GitHub: ' +
          '<a href="https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses/tree/main/docs">docs/</a></p>';
      });
  }

  window.addEventListener('hashchange', show);
  show();
})();
