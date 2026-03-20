(function() {
  var syncEnabled = true;
  window.__editorSyncPause = function() { syncEnabled = false; };
  window.__editorSyncResume = function() { syncEnabled = true; };

  // Line-anchored sync: find the topmost visible element with data-source-line
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

  // Report scroll position as line number to Swift
  var scrollTimer = null;
  function onScroll() {
    if (!syncEnabled) return;
    if (scrollTimer) clearTimeout(scrollTimer);
    scrollTimer = setTimeout(function() {
      var info = getTopVisibleLine();
      if (info && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorSync) {
        window.webkit.messageHandlers.editorSync.postMessage({
          type: 'scroll', line: info.line, fractionPast: info.fractionPast
        });
      }
    }, 30);
  }

  window.addEventListener('scroll', onScroll, {passive: true});

  // Scroll renderer to a specific source line
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

  // Expose for external queries
  window.__getTopVisibleLine = getTopVisibleLine;

  // Deprecated fraction-based API kept for scroll preservation on reload
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

  // Double-click: find the clicked text and use data-source-line for precise mapping
  document.addEventListener('dblclick', function(e) {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return;
    var word = sel.toString().trim();
    if (!word) return;

    // Walk up to find nearest element with data-source-line
    var el = sel.anchorNode;
    while (el && el !== document.body) {
      if (el.nodeType === 1 && el.hasAttribute('data-source-line')) break;
      el = el.parentNode;
    }

    if (!el || !el.hasAttribute || !el.hasAttribute('data-source-line')) {
      // Fallback: send without source line
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorSync) {
        window.webkit.messageHandlers.editorSync.postMessage({
          type: 'dblclick', word: word, sourceLine: -1, sourceCol: -1, offsetInBlock: -1
        });
      }
      return;
    }

    var sourceLine = parseInt(el.getAttribute('data-source-line'), 10);
    var sourceCol = parseInt(el.getAttribute('data-source-col') || '1', 10);

    // Character offset of clicked word within this block's text
    var offsetInBlock = -1;
    try {
      var range = sel.getRangeAt(0);
      var preRange = document.createRange();
      preRange.setStart(el, 0);
      preRange.setEnd(range.startContainer, range.startOffset);
      offsetInBlock = preRange.toString().length;
    } catch(ex) {}

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorSync) {
      window.webkit.messageHandlers.editorSync.postMessage({
        type: 'dblclick', word: word, sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock
      });
    }
  });
})();
