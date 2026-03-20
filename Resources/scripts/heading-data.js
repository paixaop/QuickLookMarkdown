(function() {
  var content = document.querySelector('.markdown-body');
  if (!content) return;

  function buildHeadingData() {
    var headings = content.querySelectorAll('h1, h2, h3, h4, h5, h6');
    if (headings.length === 0) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tocData) {
        window.webkit.messageHandlers.tocData.postMessage({ headings: [] });
      }
      return;
    }
    // Assign slug IDs (GitHub-style)
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

    // Build heading data array
    var data = [];
    headings.forEach(function(h) {
      var sourceLine = parseInt(h.getAttribute('data-source-line') || '0', 10);
      data.push({
        id: h.id,
        text: h.textContent.trim(),
        level: parseInt(h.tagName.charAt(1), 10),
        sourceLine: sourceLine
      });
    });
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tocData) {
      window.webkit.messageHandlers.tocData.postMessage({ headings: data });
    }

    // Active heading tracking via IntersectionObserver
    if (window.__tocObserver) window.__tocObserver.disconnect();
    window.__tocObserver = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting && entry.target.id) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tocData) {
            window.webkit.messageHandlers.tocData.postMessage({ activeHeadingID: entry.target.id });
          }
        }
      });
    }, { root: null, rootMargin: '0px 0px -70% 0px', threshold: 0.1 });
    headings.forEach(function(h) { window.__tocObserver.observe(h); });
  }

  // Expose for incremental updates
  window.__rebuildHeadingData = buildHeadingData;

  // Initial build
  buildHeadingData();
})();
