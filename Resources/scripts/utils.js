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

  // Calculate the character offset of a Range start within a block element's text.
  // Returns the offset or -1 on failure.
  window.__getOffsetInBlock = function(blockEl, range) {
    try {
      var preRange = document.createRange();
      preRange.setStart(blockEl, 0);
      preRange.setEnd(range.startContainer, range.startOffset);
      return preRange.toString().length;
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
