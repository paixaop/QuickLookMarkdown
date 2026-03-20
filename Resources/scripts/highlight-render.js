(function() {
  document.querySelectorAll('pre > code.language-json').forEach(function(code) {
    try {
      var obj = JSON.parse(code.textContent);
      code.textContent = JSON.stringify(obj, null, 2);
    } catch(e) {}
  });
  if (window.jsyaml) {
    document.querySelectorAll('pre > code.language-yaml, pre > code.language-yml').forEach(function(code) {
      try {
        var obj = jsyaml.load(code.textContent);
        code.textContent = jsyaml.dump(obj, { indent: 2, lineWidth: -1 });
      } catch(e) {}
    });
  }
  if (window.hljs) {
    document.querySelectorAll('pre code').forEach(function(block) {
      if (!block.classList.contains('language-mermaid')) {
        block.dataset.rawText = block.textContent;
        hljs.highlightElement(block);
      }
    });
  }
})();
