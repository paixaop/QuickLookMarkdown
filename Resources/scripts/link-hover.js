(function() {
  document.addEventListener('mouseover', function(e) {
    var a = e.target.closest('a[href]');
    if (a && a.href) {
      __postWebkitMessage('linkHover', { url: a.getAttribute('href') || a.href });
    }
  });
  document.addEventListener('mouseout', function(e) {
    var a = e.target.closest('a[href]');
    if (a) {
      __postWebkitMessage('linkHover', { url: '' });
    }
  });
})();
