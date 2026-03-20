(function() {
  window.__setupCheckboxes = function() {
    var checkboxes = document.querySelectorAll('.markdown-body input[type="checkbox"]');
    checkboxes.forEach(function(cb, index) {
      cb.disabled = false;
      cb.style.cursor = 'pointer';
      cb.addEventListener('change', function(e) {
        __postWebkitMessage('checkboxToggle', { index: index, checked: e.target.checked });
      });
    });
  };
  __setupCheckboxes();
})();
