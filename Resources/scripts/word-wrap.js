(function() {
  var wrapped = false;
  function toggle() {
    wrapped = !wrapped;
    document.querySelectorAll('pre').forEach(function(pre) {
      pre.style.whiteSpace = wrapped ? 'pre-wrap' : '';
      pre.style.wordBreak = wrapped ? 'break-all' : '';
    });
  }
  window.__toggleWordWrap = toggle;
})();
