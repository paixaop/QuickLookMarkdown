if (window.mermaid) {
  var dt = document.documentElement.getAttribute('data-theme');
  var mermaidTheme;
  if (dt === 'dark') { mermaidTheme = 'dark'; }
  else if (dt === 'light') { mermaidTheme = 'neutral'; }
  else { mermaidTheme = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral'; }
  mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: mermaidTheme });
  document.querySelectorAll('pre > code.language-mermaid').forEach(function(code, idx) {
    var graphDefinition = code.textContent || '';
    var host = document.createElement('div');
    host.className = 'mermaid';
    host.dataset.source = graphDefinition;
    var pre = code.closest('pre');
    if (pre) {
      pre.replaceWith(host);
      try {
        mermaid.render('mermaid-' + idx + '-' + Date.now(), graphDefinition)
          .then(function(result) { host.innerHTML = result.svg; })  // trusted local content from user's own markdown
          .catch(function() { host.textContent = 'Mermaid render error'; });
      } catch(e) { host.textContent = 'Mermaid render error'; }
    }
  });
}
