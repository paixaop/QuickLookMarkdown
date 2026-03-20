(function() {
  var container = document.getElementById('sidebar-container');
  if (!container) return;
  var content = document.querySelector('.markdown-body');
  if (!content) return;
  var layout = document.getElementById('layout');
  if (!layout) return;

  // Expose __buildTOC for incremental updates
  window.__buildTOC = function() {
    var headings = content.querySelectorAll('h1, h2, h3, h4, h5, h6');
    var tree = document.getElementById('toc-tree');
    if (!tree) return;
    tree.innerHTML = '';
    if (headings.length === 0) {
      // Don't hide sidebar if comments tab has content
      var commentsPanel = document.getElementById('comments-panel');
      var hasComments = commentsPanel && commentsPanel.querySelector('.comment-item');
      if (!hasComments) {
        container.classList.add('hidden');
        layout.classList.remove('has-sidebar');
      }
      return;
    }
    container.classList.remove('hidden');
    layout.classList.add('has-sidebar');
    // Assign IDs
    var slugCounts = {};
    headings.forEach(function(h) {
      var text = h.textContent || '';
      var slug = text.toLowerCase().trim()
        .replace(/[^\w\s-]/g, '').replace(/[\s]+/g, '-').replace(/^-+|-+$/g, '');
      if (!slug) slug = 'heading';
      if (slugCounts[slug] != null) { slugCounts[slug]++; slug += '-' + slugCounts[slug]; }
      else { slugCounts[slug] = 0; }
      h.id = slug;
    });
    var items = [];
    headings.forEach(function(h) {
      items.push({ el: h, level: parseInt(h.tagName.charAt(1)), children: [] });
    });
    items.forEach(function(item, idx) {
      var minLevel = items[0].level;
      var indent = item.level - minLevel;
      var hasChildren = (idx + 1 < items.length && items[idx + 1].level > item.level);
      var row = document.createElement('div');
      row.className = 'toc-item';
      row.setAttribute('data-heading-id', item.el.id);
      row.style.paddingLeft = (8 + indent * 14) + 'px';
      var toggle = document.createElement('span');
      toggle.className = 'toc-toggle';
      if (hasChildren) {
        toggle.textContent = '\u25B6';
        toggle.addEventListener('click', function(e) {
          e.stopPropagation();
          row.classList.toggle('collapsed');
          var myLevel = item.level;
          var sibling = row.nextElementSibling;
          while (sibling && sibling.classList.contains('toc-item')) {
            var sibLevel = parseInt(sibling.getAttribute('data-level'));
            if (sibLevel <= myLevel) break;
            sibling.style.display = row.classList.contains('collapsed') ? 'none' : 'flex';
            sibling = sibling.nextElementSibling;
          }
        });
      } else { toggle.classList.add('no-children'); }
      row.appendChild(toggle);
      var label = document.createElement('span');
      label.className = 'toc-label';
      label.textContent = item.el.textContent;
      label.addEventListener('click', function() { item.el.scrollIntoView({ behavior: 'smooth' }); });
      row.appendChild(label);
      row.setAttribute('data-level', item.level);
      tree.appendChild(row);
    });
    // Re-observe headings
    if (window.__tocObserver) window.__tocObserver.disconnect();
    var tocItems = tree.querySelectorAll('.toc-item');
    window.__tocObserver = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          tocItems.forEach(function(ti) { ti.classList.remove('active'); });
          var id = entry.target.id;
          var match = tree.querySelector('.toc-item[data-heading-id="' + id + '"]');
          if (match) match.classList.add('active');
        }
      });
    }, { root: content, rootMargin: '0px 0px -70% 0px', threshold: 0.1 });
    headings.forEach(function(h) { window.__tocObserver.observe(h); });
  };

  var headings = content.querySelectorAll('h1, h2, h3, h4, h5, h6');
  if (headings.length === 0) {
    container.classList.add('hidden');
    layout.classList.remove('has-toc');
    return;
  }
  layout.classList.add('has-toc');
  // Assign IDs (GitHub-style slugs)
  var slugCounts = {};
  headings.forEach(function(h) {
    var text = h.textContent || '';
    var slug = text.toLowerCase().trim()
      .replace(/[^\w\s-]/g, '').replace(/[\s]+/g, '-').replace(/^-+|-+$/g, '');
    if (!slug) slug = 'heading';
    if (slugCounts[slug] != null) { slugCounts[slug]++; slug += '-' + slugCounts[slug]; }
    else { slugCounts[slug] = 0; }
    h.id = slug;
  });
  // Build tree
  var tree = document.getElementById('toc-tree');
  var items = [];
  headings.forEach(function(h) {
    var level = parseInt(h.tagName.charAt(1));
    var item = { el: h, level: level, children: [] };
    items.push(item);
  });
  // Render flat list with indentation
  items.forEach(function(item, idx) {
    var minLevel = items[0].level;
    var indent = item.level - minLevel;
    var hasChildren = (idx + 1 < items.length && items[idx + 1].level > item.level);
    var row = document.createElement('div');
    row.className = 'toc-item';
    row.setAttribute('data-heading-id', item.el.id);
    row.style.paddingLeft = (8 + indent * 14) + 'px';
    var toggle = document.createElement('span');
    toggle.className = 'toc-toggle';
    if (hasChildren) {
      toggle.textContent = '\u25B6';
      toggle.addEventListener('click', function(e) {
        e.stopPropagation();
        row.classList.toggle('collapsed');
        // Toggle visibility of child items
        var myLevel = item.level;
        var sibling = row.nextElementSibling;
        while (sibling && sibling.classList.contains('toc-item')) {
          var sibLevel = parseInt(sibling.getAttribute('data-level'));
          if (sibLevel <= myLevel) break;
          sibling.style.display = row.classList.contains('collapsed') ? 'none' : 'flex';
          sibling = sibling.nextElementSibling;
        }
      });
    } else {
      toggle.classList.add('no-children');
    }
    row.appendChild(toggle);
    var label = document.createElement('span');
    label.className = 'toc-label';
    label.textContent = item.el.textContent;
    label.addEventListener('click', function() {
      item.el.scrollIntoView({ behavior: 'smooth' });
    });
    row.appendChild(label);
    row.setAttribute('data-level', item.level);
    tree.appendChild(row);
  });
  // Active heading tracking
  var tocItems = tree.querySelectorAll('.toc-item');
  var observer = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        tocItems.forEach(function(ti) { ti.classList.remove('active'); });
        var id = entry.target.id;
        var match = tree.querySelector('.toc-item[data-heading-id="' + id + '"]');
        if (match) match.classList.add('active');
      }
    });
  }, { root: content, rootMargin: '0px 0px -70% 0px', threshold: 0.1 });
  headings.forEach(function(h) { observer.observe(h); });
  // Toggle and resize are handled by sidebarArrangeScript
})();
