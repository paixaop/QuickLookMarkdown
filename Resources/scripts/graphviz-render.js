(function() {
  if (typeof Viz === 'undefined') return;
  var blocks = document.querySelectorAll('pre > code.language-dot, pre > code.language-graphviz');
  if (blocks.length === 0) return;
  Viz.instance().then(function(viz) {
    blocks.forEach(function(code) {
      var dot = code.textContent || '';
      var pre = code.closest('pre');
      if (!pre) return;
      try {
        var svg = viz.renderSVGElement(dot);
        var host = document.createElement('div');
        host.className = 'graphviz mermaid';
        host.appendChild(svg);
        pre.replaceWith(host);
      } catch(e) {
        var errDiv = document.createElement('div');
        errDiv.className = 'graphviz-error';
        errDiv.textContent = 'Graphviz error: ' + e.message;
        pre.replaceWith(errDiv);
      }
    });
  });
})();
