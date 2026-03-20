(function() {
  window.__setupAnchorLinks = function() {
    var body = document.querySelector('.markdown-body');
    if (!body) return;
    body.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(function(h) {
      if (!h.id) return;
      if (h.querySelector('.heading-anchor')) return;
      var a = document.createElement('a');
      a.className = 'heading-anchor';
      a.href = '#' + h.id;
      a.textContent = '#';
      a.addEventListener('click', function(e) { e.stopPropagation(); });
      h.insertBefore(a, h.firstChild);
    });
  };
  __setupAnchorLinks();
})();
