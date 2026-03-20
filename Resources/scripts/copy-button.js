(function() {
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

  // Add a copy button to a <pre> element if not already present.
  // Exposed globally so content-update.js can call it for new blocks.
  window.__addCopyButton = function(pre) {
    var code = pre.querySelector('code');
    if (!code || code.classList.contains('language-mermaid')) return;
    if (pre.querySelector('.copy-btn')) return;
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
  };

  // Initial render: add copy buttons to all code blocks.
  document.querySelectorAll('pre > code').forEach(function(code) {
    if (code.classList.contains('language-mermaid')) return;
    __addCopyButton(code.parentElement);
  });
})();
