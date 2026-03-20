(function() {
  var pref = false;
  try { pref = localStorage.getItem('line-numbers') === 'true'; } catch(e) {}
  document.querySelectorAll('pre > code').forEach(function(code) {
    if (code.classList.contains('language-mermaid') || code.classList.contains('language-dot') || code.classList.contains('language-graphviz')) return;
    var text = code.innerHTML;
    var lines = text.split('\n');
    if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
    code.innerHTML = lines.map(function(l) { return '<span class="code-line">' + l + '</span>'; }).join('');
    if (pref) code.classList.add('has-line-numbers');
  });
  function toggle() {
    var on = !document.querySelector('pre > code.has-line-numbers');
    document.querySelectorAll('pre > code').forEach(function(code) {
      if (code.classList.contains('language-mermaid') || code.classList.contains('language-dot') || code.classList.contains('language-graphviz')) return;
      if (on) code.classList.add('has-line-numbers');
      else code.classList.remove('has-line-numbers');
    });
    try { localStorage.setItem('line-numbers', on ? 'true' : 'false'); } catch(e) {}
  }
  window.__toggleLineNumbers = toggle;
  document.addEventListener('keydown', function(e) {
    if (e.metaKey && e.key === 'l') { e.preventDefault(); toggle(); }
  });
})();
