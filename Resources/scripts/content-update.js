(function() {
  // Helper: highlight a single code block (pretty-print + hljs)
  function highlightCode(code) {
    if (code.classList.contains('language-json')) {
      try { var obj = JSON.parse(code.textContent); code.textContent = JSON.stringify(obj, null, 2); } catch(e) {}
    }
    if ((code.classList.contains('language-yaml') || code.classList.contains('language-yml')) && window.jsyaml) {
      try { var obj = jsyaml.load(code.textContent); code.textContent = jsyaml.dump(obj, { indent: 2, lineWidth: -1 }); } catch(e) {}
    }
    if (window.hljs && !code.classList.contains('language-mermaid')) {
      code.dataset.rawText = code.textContent;
      hljs.highlightElement(code);
    }
  }

  // Helper: add copy button to a <pre> if not already present
  function addCopyButton(pre) {
    if (pre.querySelector('.copy-btn')) return;
    var code = pre.querySelector('code');
    if (!code || code.classList.contains('language-mermaid')) return;
    pre.style.position = 'relative';
    var btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', function(e) {
      e.preventDefault(); e.stopPropagation();
      var text = code.textContent || '';
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function() {
          btn.textContent = 'Copied!'; setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
        });
      }
    });
    pre.appendChild(btn);
  }

  // Helper: render a mermaid code block
  function renderMermaid(code, idx) {
    var graphDefinition = code.textContent || '';
    var host = document.createElement('div');
    host.className = 'mermaid';
    host.dataset.source = graphDefinition;
    var pre = code.closest('pre');
    if (pre) {
      pre.replaceWith(host);
      try {
        mermaid.render('mermaid-upd-' + idx + '-' + Date.now(), graphDefinition)
          .then(function(result) { host.innerHTML = result.svg; })
          .catch(function() { host.textContent = 'Mermaid render error'; });
      } catch(e) { host.textContent = 'Mermaid render error'; }
    }
  }

  window.__updateContent = function(html) {
    var article = document.querySelector('article.markdown-body');
    if (!article) return;
    var scrollEl = document.scrollingElement || document.documentElement;
    var savedScroll = scrollEl.scrollTop;

    // Track what changed for selective post-processing
    var changedCodeBlocks = [];
    var changedMermaidBlocks = [];
    var headingsChanged = false;
    var anyNodeChanged = false;

    if (typeof morphdom === 'function') {
      // Build a temporary container to parse new HTML
      var template = document.createElement('article');
      template.className = article.className;
      template.innerHTML = html;

      // Pre-process: convert mermaid <pre><code> in template to <div class="mermaid" data-source="...">
      // so morphdom can match them against already-rendered mermaid divs in the DOM
      template.querySelectorAll('pre > code.language-mermaid').forEach(function(code) {
        var src = code.textContent || '';
        var div = document.createElement('div');
        div.className = 'mermaid';
        div.dataset.source = src;
        div.textContent = src;
        code.closest('pre').replaceWith(div);
      });

      // Apply emoji to template before morphing so text nodes match
      if (window.__applyEmoji) __applyEmoji(template);

      morphdom(article, template, {
        childrenOnly: true,
        onBeforeElUpdated: function(fromEl, toEl) {
          // Skip already-highlighted code blocks whose raw text hasn't changed
          if (fromEl.tagName === 'CODE' && fromEl.parentElement && fromEl.parentElement.tagName === 'PRE') {
            if (fromEl.dataset.rawText && fromEl.dataset.rawText === toEl.textContent) {
              return false;
            }
          }
          // Skip mermaid divs whose source hasn't changed
          if (fromEl.classList && fromEl.classList.contains('mermaid') && fromEl.dataset.source) {
            if (fromEl.dataset.source === toEl.dataset.source) {
              return false;
            }
          }
          return true;
        },
        onElUpdated: function(el) {
          anyNodeChanged = true;
          if (el.tagName === 'CODE' && el.parentElement && el.parentElement.tagName === 'PRE') {
            changedCodeBlocks.push(el);
          }
          if (el.classList && el.classList.contains('mermaid') && el.dataset.source) {
            changedMermaidBlocks.push(el);
          }
          if (/^H[1-6]$/.test(el.tagName)) headingsChanged = true;
        },
        onNodeAdded: function(node) {
          anyNodeChanged = true;
          if (node.nodeType !== 1) return node;
          if (node.tagName === 'CODE' && node.parentElement && node.parentElement.tagName === 'PRE') {
            changedCodeBlocks.push(node);
          }
          if (node.tagName === 'PRE') {
            var code = node.querySelector('code');
            if (code) changedCodeBlocks.push(code);
          }
          if (node.classList && node.classList.contains('mermaid') && node.dataset.source) {
            changedMermaidBlocks.push(node);
          }
          if (/^H[1-6]$/.test(node.tagName)) headingsChanged = true;
          // Check children for headings
          if (node.querySelectorAll) {
            if (node.querySelectorAll('h1,h2,h3,h4,h5,h6').length > 0) headingsChanged = true;
            node.querySelectorAll('pre > code').forEach(function(c) { changedCodeBlocks.push(c); });
            node.querySelectorAll('.mermaid[data-source]').forEach(function(m) { changedMermaidBlocks.push(m); });
          }
          return node;
        },
        onBeforeNodeDiscarded: function(node) {
          if (node.nodeType === 1 && /^H[1-6]$/.test(node.tagName)) headingsChanged = true;
          return true;
        }
      });

      // Selectively highlight only changed code blocks
      changedCodeBlocks.forEach(function(code) {
        if (!code.classList.contains('language-mermaid')) {
          highlightCode(code);
        }
      });

      // Add copy buttons to parents of changed code blocks + any new pres
      changedCodeBlocks.forEach(function(code) {
        var pre = code.closest('pre');
        if (pre) addCopyButton(pre);
      });

      // Re-render only changed mermaid blocks
      if (window.mermaid && changedMermaidBlocks.length > 0) {
        var dt = document.documentElement.getAttribute('data-theme');
        var mermaidTheme;
        if (dt === 'dark') { mermaidTheme = 'dark'; }
        else if (dt === 'light') { mermaidTheme = 'neutral'; }
        else { mermaidTheme = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral'; }
        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: mermaidTheme });
        changedMermaidBlocks.forEach(function(div, idx) {
          var src = div.dataset.source || '';
          try {
            mermaid.render('mermaid-upd-' + idx + '-' + Date.now(), src)
              .then(function(result) { div.innerHTML = result.svg; })
              .catch(function() { div.textContent = 'Mermaid render error'; });
          } catch(e) { div.textContent = 'Mermaid render error'; }
        });
      }

      // Selective post-processing
      if (window.__setupCheckboxes) __setupCheckboxes();
      if (window.__setupComments) __setupComments();
      if (window.__rebuildHeadingData) __rebuildHeadingData();
      if (headingsChanged) {
        if (window.__setupAnchorLinks) __setupAnchorLinks();
      }
      if (window.__setupFootnotes) __setupFootnotes();
      if (window.__setupFrontmatter) __setupFrontmatter();

    } else {
      // Fallback: no morphdom available, replace innerHTML
      article.innerHTML = html;
      if (window.__applyEmoji) __applyEmoji();

      document.querySelectorAll('pre > code.language-json').forEach(function(code) {
        try { var obj = JSON.parse(code.textContent); code.textContent = JSON.stringify(obj, null, 2); } catch(e) {}
      });
      if (window.jsyaml) {
        document.querySelectorAll('pre > code.language-yaml, pre > code.language-yml').forEach(function(code) {
          try { var obj = jsyaml.load(code.textContent); code.textContent = jsyaml.dump(obj, { indent: 2, lineWidth: -1 }); } catch(e) {}
        });
      }
      if (window.hljs) {
        document.querySelectorAll('pre code').forEach(function(block) {
          if (!block.classList.contains('language-mermaid')) {
            block.dataset.rawText = block.textContent;
            hljs.highlightElement(block);
          }
        });
      }
      document.querySelectorAll('pre > code').forEach(function(code) {
        if (code.classList.contains('language-mermaid')) return;
        var pre = code.parentElement;
        if (pre) addCopyButton(pre);
      });
      if (window.mermaid) {
        document.querySelectorAll('pre > code.language-mermaid').forEach(function(code, idx) {
          renderMermaid(code, idx);
        });
      }
      if (window.__setupCheckboxes) __setupCheckboxes();
      if (window.__setupComments) __setupComments();
      if (window.__rebuildHeadingData) __rebuildHeadingData();
      if (window.__setupAnchorLinks) __setupAnchorLinks();
      if (window.__setupFootnotes) __setupFootnotes();
      if (window.__setupFrontmatter) __setupFrontmatter();
    }

    scrollEl.scrollTop = savedScroll;
  };
})();
