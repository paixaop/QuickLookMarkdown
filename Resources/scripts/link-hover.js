(function() {
  document.addEventListener('mouseover', function(e) {
    var a = e.target.closest('a[href]');
    if (a && a.href && window.webkit && window.webkit.messageHandlers.linkHover) {
      window.webkit.messageHandlers.linkHover.postMessage({ url: a.getAttribute('href') || a.href });
    }
  });
  document.addEventListener('mouseout', function(e) {
    var a = e.target.closest('a[href]');
    if (a && window.webkit && window.webkit.messageHandlers.linkHover) {
      window.webkit.messageHandlers.linkHover.postMessage({ url: '' });
    }
  });
})();
