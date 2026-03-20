(function() {
  var currentTooltip = null;

  function removeTooltip() {
    if (currentTooltip) {
      currentTooltip.remove();
      currentTooltip = null;
    }
  }

  function showTooltip(mark) {
    removeTooltip();
    var comment = mark.getAttribute('data-comment');
    if (!comment) return;
    var tip = document.createElement('div');
    tip.className = 'qmd-comment-tooltip';
    tip.textContent = comment;
    mark.appendChild(tip);
    currentTooltip = tip;
    // Reposition if it overflows the viewport
    var rect = tip.getBoundingClientRect();
    if (rect.top < 0) {
      tip.style.bottom = 'auto';
      tip.style.top = 'calc(100% + 4px)';
    }
    if (rect.right > window.innerWidth) {
      tip.style.left = 'auto';
      tip.style.right = '0';
    }
  }

  window.__setupComments = function() {
    var marks = document.querySelectorAll('.qmd-comment');
    marks.forEach(function(mark, index) {
      mark.dataset.commentIndex = index;
      mark.addEventListener('mouseenter', function() { showTooltip(mark); });
      mark.addEventListener('mouseleave', function() { removeTooltip(); });
      mark.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        removeTooltip();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentAction) {
          window.webkit.messageHandlers.commentAction.postMessage({
            type: 'click',
            index: index,
            comment: mark.getAttribute('data-comment') || '',
            text: mark.textContent || ''
          });
        }
        if (window.__highlightCommentInSidebar) __highlightCommentInSidebar(index);
      });
    });
  };
  __setupComments();

  // Navigate between comments
  window.__nextComment = function() {
    var marks = document.querySelectorAll('.qmd-comment');
    if (marks.length === 0) return;
    var scrollEl = (window.__getScrollContainer ? __getScrollContainer() : document.documentElement);
    var scrollTop = scrollEl.scrollTop;
    for (var i = 0; i < marks.length; i++) {
      if (marks[i].getBoundingClientRect().top > 20) {
        marks[i].scrollIntoView({ behavior: 'smooth', block: 'center' });
        showTooltip(marks[i]);
        setTimeout(removeTooltip, 2000);
        return;
      }
    }
    // Wrap around to first
    marks[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
    showTooltip(marks[0]);
    setTimeout(removeTooltip, 2000);
  };

  window.__prevComment = function() {
    var marks = document.querySelectorAll('.qmd-comment');
    if (marks.length === 0) return;
    for (var i = marks.length - 1; i >= 0; i--) {
      if (marks[i].getBoundingClientRect().top < -5) {
        marks[i].scrollIntoView({ behavior: 'smooth', block: 'center' });
        showTooltip(marks[i]);
        setTimeout(removeTooltip, 2000);
        return;
      }
    }
    // Wrap around to last
    marks[marks.length - 1].scrollIntoView({ behavior: 'smooth', block: 'center' });
    showTooltip(marks[marks.length - 1]);
    setTimeout(removeTooltip, 2000);
  };

  // Get source line info for current selection (used by comment placement)
  window.__getSelectionSourceInfo = function() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed) return null;
    var el = sel.anchorNode;
    while (el && el !== document.body) {
      if (el.nodeType === 1 && el.hasAttribute('data-source-line')) break;
      el = el.parentNode;
    }
    if (!el || !el.hasAttribute || !el.hasAttribute('data-source-line')) return null;
    var sourceLine = parseInt(el.getAttribute('data-source-line'), 10);
    var offsetInBlock = -1;
    try {
      var range = sel.getRangeAt(0);
      var preRange = document.createRange();
      preRange.setStart(el, 0);
      preRange.setEnd(range.startContainer, range.startOffset);
      offsetInBlock = preRange.toString().length;
    } catch(ex) {}
    return { sourceLine: sourceLine, offsetInBlock: offsetInBlock, text: sel.toString().trim() };
  };

  // Helpers for native context menu integration
  window.__getSelectionText = function() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed) return '';
    var article = document.querySelector('article.markdown-body');
    if (!article) return '';
    var node = sel.anchorNode;
    while (node && node !== article) node = node.parentNode;
    if (node !== article) return '';
    return sel.toString().trim();
  };

  window.__getCommentAtPoint = function(x, y) {
    var el = document.elementFromPoint(x, y);
    if (!el) return null;
    var mark = el.closest('.qmd-comment');
    if (!mark) return null;
    var index = parseInt(mark.dataset.commentIndex || '0');
    return {
      index: index,
      comment: mark.getAttribute('data-comment') || '',
      text: mark.textContent || ''
    };
  };
})();
