(function() {
  window.__setupCheckboxes = function() {
    var checkboxes = document.querySelectorAll('.markdown-body input[type="checkbox"]');
    checkboxes.forEach(function(cb, index) {
      cb.disabled = false;
      cb.style.cursor = 'pointer';
      cb.addEventListener('change', function(e) {
        var checked = e.target.checked;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.checkboxToggle) {
          window.webkit.messageHandlers.checkboxToggle.postMessage({index: index, checked: checked});
        }
      });
    });
  };
  __setupCheckboxes();
})();
