(function() {
  if (!window.mermaid) return;

  // Render a single mermaid code block into an SVG div.
  // Exposed globally so content-update.js can call it for changed blocks.
  // Note: innerHTML assignment uses trusted SVG output from mermaid.render()
  // which processes the user's own local markdown content.
  window.__renderMermaidBlock = function(code, idx) {
    var graphDefinition = code.textContent || '';
    var host = document.createElement('div');
    host.className = 'mermaid';
    host.dataset.source = graphDefinition;
    var pre = code.closest('pre');
    if (!pre) return;
    pre.replaceWith(host);
    try {
      mermaid.render('mermaid-' + idx + '-' + Date.now(), graphDefinition)
        .then(function(result) { host.innerHTML = result.svg; }) // trusted local content from user's own markdown
        .catch(function() { host.textContent = 'Mermaid render error'; });
    } catch(e) { host.textContent = 'Mermaid render error'; }
  };

  // Initialize mermaid with theme from utils.js and render all blocks.
  mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: __getMermaidTheme() });
  document.querySelectorAll('pre > code.language-mermaid').forEach(function(code, idx) {
    __renderMermaidBlock(code, idx);
  });
})();
