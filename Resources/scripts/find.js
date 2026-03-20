(function() {
  var bar, input, counter, highlights = [], currentIdx = -1;
  function clearHighlights() {
    highlights.forEach(function(span) {
      var parent = span.parentNode;
      if (parent) { parent.replaceChild(document.createTextNode(span.textContent), span); parent.normalize(); }
    });
    highlights = []; currentIdx = -1;
  }
  function updateCounter() {
    if (!counter) return;
    if (highlights.length === 0) { counter.textContent = ''; return; }
    counter.textContent = (currentIdx + 1) + '/' + highlights.length;
  }
  function scrollToCurrent() {
    highlights.forEach(function(h) { h.className = 'find-highlight'; });
    if (currentIdx >= 0 && currentIdx < highlights.length) {
      highlights[currentIdx].className = 'find-highlight find-highlight-active';
      highlights[currentIdx].scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
    updateCounter();
  }
  function doSearch(query) {
    clearHighlights();
    if (!query) { updateCounter(); return; }
    var body = document.querySelector('.markdown-body') || document.body;
    var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null);
    var textNodes = [];
    while (walker.nextNode()) textNodes.push(walker.currentNode);
    var lowerQ = query.toLowerCase();
    textNodes.forEach(function(node) {
      var text = node.textContent;
      var lower = text.toLowerCase();
      var idx = lower.indexOf(lowerQ);
      if (idx === -1) return;
      var frag = document.createDocumentFragment();
      var pos = 0;
      while (idx !== -1) {
        if (idx > pos) frag.appendChild(document.createTextNode(text.substring(pos, idx)));
        var span = document.createElement('span');
        span.className = 'find-highlight';
        span.textContent = text.substring(idx, idx + query.length);
        frag.appendChild(span);
        highlights.push(span);
        pos = idx + query.length;
        idx = lower.indexOf(lowerQ, pos);
      }
      if (pos < text.length) frag.appendChild(document.createTextNode(text.substring(pos)));
      node.parentNode.replaceChild(frag, node);
    });
    if (highlights.length > 0) { currentIdx = 0; scrollToCurrent(); }
    else { updateCounter(); }
  }
  function openBar() {
    if (bar) { input.focus(); input.select(); return; }
    bar = document.createElement('div');
    bar.id = 'find-bar';
    input = document.createElement('input');
    input.type = 'text';
    input.placeholder = 'Find...';
    counter = document.createElement('span');
    counter.className = 'find-counter';
    var closeBtn = document.createElement('button');
    closeBtn.textContent = '\u00D7';
    closeBtn.addEventListener('click', function() { closeBar(); });
    bar.appendChild(input);
    bar.appendChild(counter);
    bar.appendChild(closeBtn);
    document.body.appendChild(bar);
    input.focus();
    var debounce;
    input.addEventListener('input', function() {
      clearTimeout(debounce);
      debounce = setTimeout(function() { doSearch(input.value); }, 150);
    });
    input.addEventListener('keydown', function(ev) {
      if (ev.key === 'Escape') { closeBar(); return; }
      if (ev.key === 'Enter') {
        if (highlights.length === 0) return;
        if (ev.shiftKey) { currentIdx = (currentIdx - 1 + highlights.length) % highlights.length; }
        else { currentIdx = (currentIdx + 1) % highlights.length; }
        scrollToCurrent();
      }
    });
  }
  function closeBar() {
    clearHighlights();
    if (bar) { bar.remove(); bar = null; }
  }
  window.__findOpen = openBar;
  // Expose search API for SwiftUI search bar
  window.__searchHighlight = function(query) { doSearch(query); return highlights.length; };
  window.__searchNext = function() { if (highlights.length === 0) return -1; currentIdx = (currentIdx + 1) % highlights.length; scrollToCurrent(); return currentIdx; };
  window.__searchPrev = function() { if (highlights.length === 0) return -1; currentIdx = (currentIdx - 1 + highlights.length) % highlights.length; scrollToCurrent(); return currentIdx; };
  window.__searchClear = function() { clearHighlights(); };
  window.__searchCount = function() { return highlights.length; };
  window.__searchCurrentIndex = function() { return currentIdx; };
  document.addEventListener('keydown', function(e) {
    if (e.metaKey && e.key === 'f') { e.preventDefault(); openBar(); }
  });
})();
