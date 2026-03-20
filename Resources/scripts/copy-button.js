(function() {
  document.querySelectorAll('pre > code').forEach(function(code) {
    if (code.classList.contains('language-mermaid')) return;
    var pre = code.parentElement;
    if (!pre || pre.querySelector('.copy-btn')) return;
    pre.style.position = 'relative';
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      var text = code.textContent || '';
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function() {
          btn.textContent = 'Copied!';
          setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
        }).catch(function() { fallbackCopy(text, btn); });
      } else {
        fallbackCopy(text, btn);
      }
    });
    pre.appendChild(btn);
  });
  function fallbackCopy(text, btn) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand('copy');
      btn.textContent = 'Copied!';
      setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
    } catch(e) {}
    document.body.removeChild(ta);
  }
})();
