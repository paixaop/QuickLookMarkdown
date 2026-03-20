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
    // Reposition if it overflows the viewport.
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

  function showTooltipBriefly(mark) {
    showTooltip(mark);
    setTimeout(removeTooltip, 2000);
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
        __postWebkitMessage('commentAction', {
          type: 'click',
          index: index,
          comment: mark.getAttribute('data-comment') || '',
          text: mark.textContent || ''
        });
      });
    });
  };
  __setupComments();

  // Navigate between comments.
  window.__nextComment = function() {
    var marks = document.querySelectorAll('.qmd-comment');
    if (marks.length === 0) return;
    for (var i = 0; i < marks.length; i++) {
      if (marks[i].getBoundingClientRect().top > 20) {
        marks[i].scrollIntoView({ behavior: 'smooth', block: 'center' });
        showTooltipBriefly(marks[i]);
        return;
      }
    }
    marks[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
    showTooltipBriefly(marks[0]);
  };

  window.__prevComment = function() {
    var marks = document.querySelectorAll('.qmd-comment');
    if (marks.length === 0) return;
    for (var i = marks.length - 1; i >= 0; i--) {
      if (marks[i].getBoundingClientRect().top < -5) {
        marks[i].scrollIntoView({ behavior: 'smooth', block: 'center' });
        showTooltipBriefly(marks[i]);
        return;
      }
    }
    var last = marks[marks.length - 1];
    last.scrollIntoView({ behavior: 'smooth', block: 'center' });
    showTooltipBriefly(last);
  };

  // Get source line info for current selection (used by comment placement).
  window.__getSelectionSourceInfo = function() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed) return null;
    var el = __findSourceLineAncestor(sel.anchorNode);
    if (!el) return null;
    var sourceLine = parseInt(el.getAttribute('data-source-line'), 10);
    var offsetInBlock = sel.rangeCount > 0 ? __getOffsetInBlock(el, sel.getRangeAt(0)) : -1;
    return { sourceLine: sourceLine, offsetInBlock: offsetInBlock, text: sel.toString().trim() };
  };

  // Helpers for native context menu integration.
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
    return {
      index: parseInt(mark.dataset.commentIndex || '0'),
      comment: mark.getAttribute('data-comment') || '',
      text: mark.textContent || ''
    };
  };
})();
