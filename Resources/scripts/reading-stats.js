(function() {
  if (document.documentElement.getAttribute('data-filetype') !== 'markdown') return;
  var body = document.querySelector('.markdown-body');
  if (!body) return;
  var text = body.textContent || '';
  var words = text.trim().split(/\s+/).filter(function(w) { return w.length > 0; }).length;
  var minutes = Math.max(1, Math.round(words / 200));
  var stats = document.createElement('div');
  stats.className = 'reading-stats';
  stats.textContent = words.toLocaleString() + ' words \u00B7 ' + minutes + ' min read';
  body.insertBefore(stats, body.firstChild);
})();
