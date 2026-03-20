(function() {
  var root = document.documentElement;
  var current = 16;
  var min = 10, max = 32, step = 2;
  document.addEventListener('keydown', function(e) {
    if (!e.metaKey) return;
    if (e.key === '=' || e.key === '+') {
      e.preventDefault();
      current = Math.min(current + step, max);
      root.style.fontSize = current + 'px';
    } else if (e.key === '-') {
      e.preventDefault();
      current = Math.max(current - step, min);
      root.style.fontSize = current + 'px';
    } else if (e.key === '0') {
      e.preventDefault();
      current = 16;
      root.style.fontSize = '';
    }
  });
})();
