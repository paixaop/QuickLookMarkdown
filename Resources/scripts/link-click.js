(function() {
  document.addEventListener('click', function(e) {
    var a = e.target.closest('a[href]');
    if (!a) return;
    var rawHref = a.getAttribute('href') || '';
    var href = a.href;
    if (!href) return;
    // Fragment-only link — handle via scrollIntoView for reliability.
    if (rawHref.indexOf('#') === 0) {
      e.preventDefault();
      var target = document.getElementById(rawHref.substring(1));
      if (target) target.scrollIntoView({ behavior: 'smooth' });
      return;
    }
    // Same-page anchor links (e.g. file.md#section where file.md is current page).
    if (a.hash && a.pathname === location.pathname) {
      e.preventDefault();
      var target2 = document.getElementById(a.hash.substring(1));
      if (target2) target2.scrollIntoView({ behavior: 'smooth' });
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    __postWebkitMessage('linkClick', { url: href });
  }, true);
})();
