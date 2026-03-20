(function() {
  // Highlight a single code element: pretty-print JSON/YAML, then apply hljs.
  // Exposed globally so content-update.js can call it for changed blocks.
  window.__highlightCode = function(code) {
    if (code.classList.contains('language-json')) {
      try { var obj = JSON.parse(code.textContent); code.textContent = JSON.stringify(obj, null, 2); } catch(e) {}
    }
    if ((code.classList.contains('language-yaml') || code.classList.contains('language-yml')) && window.jsyaml) {
      try { var obj = jsyaml.load(code.textContent); code.textContent = jsyaml.dump(obj, { indent: 2, lineWidth: -1 }); } catch(e) {}
    }
    if (window.hljs && !code.classList.contains('language-mermaid')) {
      code.dataset.rawText = code.textContent;
      hljs.highlightElement(code);
    }
  };

  // Initial render: highlight all code blocks on page load.
  document.querySelectorAll('pre code').forEach(function(code) {
    if (!code.classList.contains('language-mermaid')) {
      __highlightCode(code);
    }
  });
})();
