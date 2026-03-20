(function() {
  window.__buildFileTree = function(tree, currentFile) {
    var container = document.getElementById('files-tree');
    if (!container) return;
    container.textContent = '';

    function renderTree(nodes, parent, depth) {
      nodes.forEach(function(node) {
        if (node.type === 'dir') {
          var dirRow = document.createElement('div');
          dirRow.className = 'file-item';
          dirRow.style.paddingLeft = (4 + depth * 14) + 'px';

          var toggle = document.createElement('span');
          toggle.className = 'dir-toggle expanded';
          toggle.textContent = '\u25B6';

          var icon = document.createElement('span');
          icon.className = 'file-item-icon';
          icon.textContent = '\uD83D\uDCC1';

          var label = document.createElement('span');
          label.className = 'file-item-label';
          label.textContent = node.name;
          label.style.fontWeight = '600';

          dirRow.appendChild(toggle);
          dirRow.appendChild(icon);
          dirRow.appendChild(label);
          parent.appendChild(dirRow);

          var childContainer = document.createElement('div');
          childContainer.className = 'dir-children';

          toggle.addEventListener('click', function(e) {
            e.stopPropagation();
            toggle.classList.toggle('expanded');
            childContainer.classList.toggle('collapsed');
          });
          dirRow.addEventListener('click', function() {
            toggle.classList.toggle('expanded');
            childContainer.classList.toggle('collapsed');
          });

          if (node.children) {
            renderTree(node.children, childContainer, depth + 1);
          }
          parent.appendChild(childContainer);
        } else {
          var row = document.createElement('div');
          row.className = 'file-item';
          if (node.path === currentFile) row.classList.add('active');
          row.style.paddingLeft = (18 + depth * 14) + 'px';

          var fIcon = document.createElement('span');
          fIcon.className = 'file-item-icon';
          fIcon.textContent = '\uD83D\uDCC4';

          var fLabel = document.createElement('span');
          fLabel.className = 'file-item-label';
          fLabel.textContent = node.name;

          row.appendChild(fIcon);
          row.appendChild(fLabel);
          row.addEventListener('click', function() {
            if (window.webkit && window.webkit.messageHandlers.fileClick) {
              window.webkit.messageHandlers.fileClick.postMessage({ path: node.path });
            }
          });
          parent.appendChild(row);
        }
      });
    }

    renderTree(tree, container, 0);
  };

  window.__showFilesPanel = function() {
    var container = document.getElementById('sidebar-container');
    if (!container) return;
    container.classList.remove('collapsed');
    container.classList.remove('hidden');
    var layout = document.getElementById('layout');
    if (layout) layout.classList.add('has-sidebar');
    var icons = container.querySelectorAll('.sidebar-icon');
    icons.forEach(function(i) { i.classList.remove('active'); });
    var filesIcon = container.querySelector('.sidebar-icon[data-panel="files"]');
    if (filesIcon) filesIcon.classList.add('active');
    container.querySelectorAll('.sidebar-panel').forEach(function(p) {
      p.classList.toggle('active', p.id === 'files-panel');
    });
  };
})();
