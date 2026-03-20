(function() {
  document.addEventListener('click', function(e) {
    var a = e.target.closest('a[href]');
    if (!a) return;
    var rawHref = a.getAttribute('href') || '';
    var href = a.href;
    if (!href) return;
    // Let anchor/fragment links scroll natively within the page
    if (rawHref.indexOf('#') === 0) {
      // Fragment-only link — handle via scrollIntoView for reliability
      e.preventDefault();
      var id = rawHref.substring(1);
      var target = document.getElementById(id);
      if (target) target.scrollIntoView({ behavior: 'smooth' });
      return;
    }
    // Same-page anchor links (e.g. file.md#section where file.md is current page)
    if (a.hash && a.pathname === location.pathname) {
      e.preventDefault();
      var id2 = a.hash.substring(1);
      var target2 = document.getElementById(id2);
      if (target2) target2.scrollIntoView({ behavior: 'smooth' });
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkClick) {
      window.webkit.messageHandlers.linkClick.postMessage({ url: href });
    }
  }, true);
})();
