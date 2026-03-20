(function() {
  var bar = null;
  function close() { if (bar) { bar.remove(); bar = null; } }
  function openJump() {
    if (bar) { close(); return; }
    bar = document.createElement('div');
    bar.id = 'jump-bar';
    var inp = document.createElement('input');
    inp.type = 'number'; inp.min = '1'; inp.placeholder = 'Line #';
    bar.appendChild(inp);
    document.body.appendChild(bar);
    inp.focus();
    inp.addEventListener('keydown', function(ev) {
      if (ev.key === 'Escape') { close(); return; }
      if (ev.key === 'Enter') {
        var n = parseInt(inp.value);
        if (!n || n < 1) return;
        var lines = document.querySelectorAll('.code-line');
        if (n > lines.length) n = lines.length;
        var target = lines[n - 1];
        if (target) {
          target.scrollIntoView({ behavior: 'smooth', block: 'center' });
          target.classList.add('line-flash');
          setTimeout(function() { target.classList.remove('line-flash'); }, 1000);
        }
        close();
      }
    });
  }
  window.__jumpToLine = openJump;
  document.addEventListener('keydown', function(e) {
    if (e.metaKey && e.key === 'g') { e.preventDefault(); openJump(); }
  });
})();
