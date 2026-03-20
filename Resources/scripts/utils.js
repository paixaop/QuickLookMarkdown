// Shared utilities used by multiple scripts.
// Must be loaded BEFORE all other scripts.
(function() {
  // Post a message to a WebKit message handler with guard checks.
  window.__postWebkitMessage = function(handler, payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[handler]) {
      window.webkit.messageHandlers[handler].postMessage(payload);
    }
  };

  // Walk up from a DOM node to find the nearest ancestor with data-source-line.
  // Returns the element or null.
  window.__findSourceLineAncestor = function(node) {
    var el = node;
    while (el && el !== document.body) {
      if (el.nodeType === 1 && el.hasAttribute('data-source-line')) return el;
      el = el.parentNode;
    }
    return null;
  };

  // Calculate the character offset of a Range start within a block element's text,
  // excluding heading anchor elements injected by anchor-links.js.
  // Returns the offset or -1 on failure.
  window.__getOffsetInBlock = function(blockEl, range) {
    try {
      var preRange = document.createRange();
      preRange.setStart(blockEl, 0);
      preRange.setEnd(range.startContainer, range.startOffset);
      var offset = preRange.toString().length;
      // Subtract text from heading anchors (injected "#" links not in source)
      var anchors = blockEl.querySelectorAll('.heading-anchor');
      for (var i = 0; i < anchors.length; i++) {
        var aRange = document.createRange();
        aRange.selectNode(anchors[i]);
        // Only subtract if the anchor is before the selection start
        if (aRange.compareBoundaryPoints(Range.END_TO_START, range) <= 0) {
          offset -= anchors[i].textContent.length;
        }
      }
      return Math.max(0, offset);
    } catch(e) {
      return -1;
    }
  };

  // Calculate the character offset of a Range end within a block element's text,
  // excluding heading anchor elements. Companion to __getOffsetInBlock.
  window.__getEndOffsetInBlock = function(blockEl, range) {
    try {
      var endRange = document.createRange();
      endRange.setStart(blockEl, 0);
      endRange.setEnd(range.endContainer, range.endOffset);
      var offset = endRange.toString().length;
      var anchors = blockEl.querySelectorAll('.heading-anchor');
      for (var i = 0; i < anchors.length; i++) {
        var aRange = document.createRange();
        aRange.selectNode(anchors[i]);
        if (aRange.compareBoundaryPoints(Range.END_TO_END, range) <= 0) {
          offset -= anchors[i].textContent.length;
        }
      }
      return Math.max(0, offset);
    } catch(e) {
      return -1;
    }
  };

  // Determine the mermaid theme based on the current document theme.
  window.__getMermaidTheme = function() {
    var dt = document.documentElement.getAttribute('data-theme');
    if (dt === 'dark') return 'dark';
    if (dt === 'light') return 'neutral';
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral';
  };
})();
