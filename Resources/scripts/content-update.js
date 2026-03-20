(function() {
  // Shared post-processing: run all setup hooks after content changes.
  function runPostProcessing(headingsChanged) {
    if (window.__setupCheckboxes) __setupCheckboxes();
    if (window.__setupComments) __setupComments();
    if (window.__rebuildHeadingData) __rebuildHeadingData();
    if (headingsChanged && window.__setupAnchorLinks) __setupAnchorLinks();
    if (window.__setupFootnotes) __setupFootnotes();
    if (window.__setupFrontmatter) __setupFrontmatter();
  }

  // Highlight changed code blocks and add copy buttons.
  function processCodeBlocks(codeBlocks) {
    codeBlocks.forEach(function(code) {
      if (!code.classList.contains('language-mermaid')) {
        __highlightCode(code);
      }
      var pre = code.closest('pre');
      if (pre) __addCopyButton(pre);
    });
  }

  // Re-render changed mermaid blocks with current theme.
  // Uses innerHTML with trusted SVG output from mermaid.render()
  // which processes the user's own local markdown content.
  function processMermaidBlocks(mermaidBlocks) {
    if (!window.mermaid || mermaidBlocks.length === 0) return;
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: __getMermaidTheme() });
    mermaidBlocks.forEach(function(div, idx) {
      var src = div.dataset.source || '';
      try {
        mermaid.render('mermaid-upd-' + idx + '-' + Date.now(), src)
          .then(function(result) { div.innerHTML = result.svg; })
          .catch(function() { div.textContent = 'Mermaid render error'; });
      } catch(e) { div.textContent = 'Mermaid render error'; }
    });
  }

  // Check if a node is or contains headings.
  function hasHeadings(node) {
    if (/^H[1-6]$/.test(node.tagName)) return true;
    return node.querySelectorAll && node.querySelectorAll('h1,h2,h3,h4,h5,h6').length > 0;
  }

  // Collect code and mermaid blocks from a node and its children.
  function collectBlocks(node, codeBlocks, mermaidBlocks) {
    if (node.tagName === 'CODE' && node.parentElement && node.parentElement.tagName === 'PRE') {
      codeBlocks.push(node);
    }
    if (node.tagName === 'PRE') {
      var code = node.querySelector('code');
      if (code) codeBlocks.push(code);
    }
    if (node.classList && node.classList.contains('mermaid') && node.dataset.source) {
      mermaidBlocks.push(node);
    }
    if (node.querySelectorAll) {
      node.querySelectorAll('pre > code').forEach(function(c) { codeBlocks.push(c); });
      node.querySelectorAll('.mermaid[data-source]').forEach(function(m) { mermaidBlocks.push(m); });
    }
  }

  // Incremental update using morphdom.
  // Uses innerHTML with trusted content from the user's own local markdown files.
  function updateWithMorphdom(article, html) {
    var template = document.createElement('article');
    template.className = article.className;
    template.innerHTML = html;

    // Convert mermaid <pre><code> to <div class="mermaid"> so morphdom can match rendered blocks.
    template.querySelectorAll('pre > code.language-mermaid').forEach(function(code) {
      var div = document.createElement('div');
      div.className = 'mermaid';
      div.dataset.source = code.textContent || '';
      div.textContent = div.dataset.source;
      code.closest('pre').replaceWith(div);
    });

    if (window.__applyEmoji) __applyEmoji(template);

    var changedCodeBlocks = [];
    var changedMermaidBlocks = [];
    var headingsChanged = false;

    morphdom(article, template, {
      childrenOnly: true,
      onBeforeElUpdated: function(fromEl, toEl) {
        // Skip already-highlighted code blocks whose raw text hasn't changed.
        if (fromEl.tagName === 'CODE' && fromEl.parentElement && fromEl.parentElement.tagName === 'PRE') {
          if (fromEl.dataset.rawText && fromEl.dataset.rawText === toEl.textContent) return false;
        }
        // Skip mermaid divs whose source hasn't changed.
        if (fromEl.classList && fromEl.classList.contains('mermaid') && fromEl.dataset.source) {
          if (fromEl.dataset.source === toEl.dataset.source) return false;
        }
        return true;
      },
      onElUpdated: function(el) {
        if (el.tagName === 'CODE' && el.parentElement && el.parentElement.tagName === 'PRE') {
          changedCodeBlocks.push(el);
        }
        if (el.classList && el.classList.contains('mermaid') && el.dataset.source) {
          changedMermaidBlocks.push(el);
        }
        if (/^H[1-6]$/.test(el.tagName)) headingsChanged = true;
      },
      onNodeAdded: function(node) {
        if (node.nodeType !== 1) return node;
        collectBlocks(node, changedCodeBlocks, changedMermaidBlocks);
        if (hasHeadings(node)) headingsChanged = true;
        return node;
      },
      onBeforeNodeDiscarded: function(node) {
        if (node.nodeType === 1 && /^H[1-6]$/.test(node.tagName)) headingsChanged = true;
        return true;
      }
    });

    processCodeBlocks(changedCodeBlocks);
    processMermaidBlocks(changedMermaidBlocks);
    runPostProcessing(headingsChanged);
  }

  // Full replacement fallback when morphdom is not available.
  // Uses innerHTML with trusted content from the user's own local markdown files.
  function updateWithReplacement(article, html) {
    article.innerHTML = html;
    if (window.__applyEmoji) __applyEmoji();

    document.querySelectorAll('pre code').forEach(function(code) {
      if (!code.classList.contains('language-mermaid')) __highlightCode(code);
    });
    document.querySelectorAll('pre > code').forEach(function(code) {
      if (!code.classList.contains('language-mermaid')) __addCopyButton(code.parentElement);
    });
    if (window.mermaid) {
      document.querySelectorAll('pre > code.language-mermaid').forEach(function(code, idx) {
        __renderMermaidBlock(code, idx);
      });
    }
    runPostProcessing(true);
  }

  window.__updateContent = function(html) {
    var article = document.querySelector('article.markdown-body');
    if (!article) return;
    var scrollEl = document.scrollingElement || document.documentElement;
    var savedScroll = scrollEl.scrollTop;

    if (typeof morphdom === 'function') {
      updateWithMorphdom(article, html);
    } else {
      updateWithReplacement(article, html);
    }

    scrollEl.scrollTop = savedScroll;
  };
})();
