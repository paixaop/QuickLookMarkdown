(function() {
  window.__buildCommentsList = function() {
    var list = document.getElementById('comments-list');
    if (!list) return;
    list.innerHTML = '';
    var marks = document.querySelectorAll('.qmd-comment');
    var sidebar = document.getElementById('sidebar-container');
    var layout = document.getElementById('layout');
    if (marks.length === 0) {
      // Update comments icon badge
      var badge = document.querySelector('.sidebar-icon[data-panel="comments"] .comment-badge');
      if (badge) badge.remove();
      return;
    }
    // Show sidebar if comments exist
    if (sidebar && layout) {
      sidebar.classList.remove('hidden');
      layout.classList.add('has-sidebar');
    }
    // Update badge count
    var commentsIcon = document.querySelector('.sidebar-icon[data-panel="comments"]');
    if (commentsIcon) {
      var badge = commentsIcon.querySelector('.comment-badge');
      if (!badge) {
        badge = document.createElement('span');
        badge.className = 'comment-badge';
        commentsIcon.appendChild(badge);
      }
      badge.textContent = marks.length;
    }

    marks.forEach(function(mark, index) {
      var item = document.createElement('div');
      item.className = 'comment-item';
      item.dataset.index = index;

      var textEl = document.createElement('div');
      textEl.className = 'comment-annotated';
      var annotated = mark.textContent || '';
      textEl.textContent = annotated.length > 60 ? annotated.substring(0, 57) + '...' : annotated;
      textEl.title = annotated;
      item.appendChild(textEl);

      var commentEl = document.createElement('div');
      commentEl.className = 'comment-text';
      commentEl.textContent = mark.getAttribute('data-comment') || '';
      item.appendChild(commentEl);

      var actions = document.createElement('div');
      actions.className = 'comment-actions';
      var editBtn = document.createElement('button');
      editBtn.className = 'comment-action-btn';
      editBtn.textContent = '\u270E';
      editBtn.title = 'Edit comment';
      editBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentAction) {
          window.webkit.messageHandlers.commentAction.postMessage({
            type: 'click',
            index: index,
            comment: mark.getAttribute('data-comment') || '',
            text: mark.textContent || ''
          });
        }
      });
      actions.appendChild(editBtn);

      var delBtn = document.createElement('button');
      delBtn.className = 'comment-action-btn comment-delete-btn';
      delBtn.textContent = '\u2715';
      delBtn.title = 'Delete comment';
      delBtn.addEventListener('click', function(e) {
        e.stopPropagation();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentAction) {
          window.webkit.messageHandlers.commentAction.postMessage({
            type: 'sidebarDelete',
            index: index
          });
        }
      });
      actions.appendChild(delBtn);
      item.appendChild(actions);

      // Click to navigate
      item.addEventListener('click', function() {
        mark.scrollIntoView({ behavior: 'smooth', block: 'center' });
        mark.classList.add('qmd-comment-flash');
        setTimeout(function() { mark.classList.remove('qmd-comment-flash'); }, 1500);
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentAction) {
          window.webkit.messageHandlers.commentAction.postMessage({
            type: 'sidebarClick',
            index: index
          });
        }
        __highlightCommentInSidebar(index);
      });

      list.appendChild(item);
    });
  };

  window.__highlightCommentInSidebar = function(index) {
    var list = document.getElementById('comments-list');
    if (!list) return;
    list.querySelectorAll('.comment-item').forEach(function(item) {
      item.classList.toggle('active', parseInt(item.dataset.index) === index);
    });
    var active = list.querySelector('.comment-item.active');
    if (active) active.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  };

  __buildCommentsList();
})();
