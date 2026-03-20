(function() {
  var container = document.getElementById('sidebar-container');
  if (!container) return;
  var layout = document.getElementById('layout');

  // Icon tab switching
  var icons = container.querySelectorAll('.sidebar-icon');
  icons.forEach(function(icon) {
    icon.addEventListener('click', function() {
      var panel = icon.dataset.panel;
      // If clicking the active icon, toggle sidebar collapse
      if (icon.classList.contains('active') && !container.classList.contains('collapsed')) {
        container.classList.add('collapsed');
        return;
      }
      container.classList.remove('collapsed');
      icons.forEach(function(i) { i.classList.remove('active'); });
      icon.classList.add('active');
      container.querySelectorAll('.sidebar-panel').forEach(function(p) {
        p.classList.toggle('active', p.id === panel + '-panel');
      });
    });
  });

  // Resize handle
  var resize = document.getElementById('sidebar-resize');
  if (resize) {
    resize.addEventListener('mousedown', function(e) {
      e.preventDefault();
      if (container.classList.contains('collapsed')) return;
      var startX = e.clientX, startW = container.offsetWidth;
      resize.classList.add('dragging');
      document.body.classList.add('sidebar-resizing');
      function onMove(ev) {
        var nw = Math.max(100, Math.min(startW + (ev.clientX - startX), window.innerWidth * 0.5));
        container.style.width = nw + 'px';
      }
      function onUp() {
        resize.classList.remove('dragging');
        document.body.classList.remove('sidebar-resizing');
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
      }
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  }

  // Show sidebar when comments are added (switch to comments tab)
  window.__showCommentsPanel = function() {
    if (!container) return;
    container.classList.remove('collapsed');
    icons.forEach(function(i) { i.classList.remove('active'); });
    var commentsIcon = container.querySelector('.sidebar-icon[data-panel="comments"]');
    if (commentsIcon) commentsIcon.classList.add('active');
    container.querySelectorAll('.sidebar-panel').forEach(function(p) {
      p.classList.toggle('active', p.id === 'comments-panel');
    });
  };

  // Toggle sidebar visibility
  window.__toggleSidebar = function() {
    if (!container || !layout) return;
    if (container.classList.contains('hidden')) {
      container.classList.remove('hidden');
      layout.classList.add('has-sidebar');
    } else {
      container.classList.add('hidden');
      layout.classList.remove('has-sidebar');
    }
  };
})();
