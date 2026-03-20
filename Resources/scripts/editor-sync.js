(function() {
  var syncEnabled = true;
  window.__editorSyncPause = function() { syncEnabled = false; };
  window.__editorSyncResume = function() { syncEnabled = true; };

  // Line-anchored sync: find the topmost visible element with data-source-line.
  function getTopVisibleLine() {
    var elements = document.querySelectorAll('[data-source-line]');
    for (var i = 0; i < elements.length; i++) {
      var rect = elements[i].getBoundingClientRect();
      if (rect.bottom > 0) {
        var line = parseInt(elements[i].getAttribute('data-source-line'), 10);
        var fractionPast = 0;
        if (rect.top < 0 && rect.height > 0) {
          fractionPast = Math.min(1, -rect.top / rect.height);
        }
        return { line: line, fractionPast: fractionPast };
      }
    }
    return null;
  }

  // Report scroll position as line number to Swift.
  var scrollTimer = null;
  function onScroll() {
    if (!syncEnabled) return;
    if (scrollTimer) clearTimeout(scrollTimer);
    scrollTimer = setTimeout(function() {  // ~1 frame delay to batch scroll events
      var info = getTopVisibleLine();
      if (info) {
        __postWebkitMessage('editorSync', { type: 'scroll', line: info.line, fractionPast: info.fractionPast });
      }
    }, 16);
  }

  window.addEventListener('scroll', onScroll, { passive: true });

  // Scroll renderer to a specific source line.
  window.__scrollToLine = function(line, fractionPast) {
    fractionPast = fractionPast || 0;
    var elements = document.querySelectorAll('[data-source-line]');
    var target = null;
    for (var i = 0; i < elements.length; i++) {
      var elLine = parseInt(elements[i].getAttribute('data-source-line'), 10);
      if (elLine <= line) target = elements[i];
      else break;
    }
    if (target) {
      var rect = target.getBoundingClientRect();
      var scrollOffset = rect.top + window.scrollY - (fractionPast * rect.height);
      window.scrollTo({ top: Math.max(0, scrollOffset), behavior: 'auto' });
    }
  };

  window.__getTopVisibleLine = getTopVisibleLine;

  // Deprecated fraction-based API kept for scroll preservation on reload.
  window.__getScrollFraction = function() {
    var el = document.documentElement;
    var maxScroll = el.scrollHeight - el.clientHeight;
    return maxScroll > 0 ? el.scrollTop / maxScroll : 0;
  };
  window.__setScrollFraction = function(fraction) {
    var el = document.documentElement;
    var maxScroll = el.scrollHeight - el.clientHeight;
    if (maxScroll > 0) el.scrollTop = fraction * maxScroll;
  };

  // Double-click: find the clicked text and use data-source-line for precise mapping.
  document.addEventListener('dblclick', function(e) {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return;
    var word = sel.toString().trim();
    if (!word) return;

    var el = __findSourceLineAncestor(sel.anchorNode);

    if (!el) {
      __postWebkitMessage('editorSync', {
        type: 'dblclick', word: word, sourceLine: -1, sourceCol: -1, offsetInBlock: -1
      });
      return;
    }

    var sourceLine = parseInt(el.getAttribute('data-source-line'), 10);
    var sourceCol = parseInt(el.getAttribute('data-source-col') || '1', 10);
    var range = sel.rangeCount > 0 ? sel.getRangeAt(0) : null;
    var offsetInBlock = range ? __getOffsetInBlock(el, range) : -1;
    var endOffsetInBlock = range ? __getEndOffsetInBlock(el, range) : -1;

    __postWebkitMessage('editorSync', {
      type: 'dblclick', word: word, sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock
    });
  });
})();
