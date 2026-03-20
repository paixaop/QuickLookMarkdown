(function() {
  window.__setupFootnotes = function() {
    var body = document.querySelector('.markdown-body');
    if (!body) return;
    // Remove existing footnotes section before rebuilding
    var existing = body.querySelector('section.footnotes');
    if (existing) existing.remove();
  var defs = {};
  var paras = body.querySelectorAll('p');
  var defParas = [];
  paras.forEach(function(p) {
    var text = p.textContent || '';
    var m = text.match(/^\[\^([^\]]+)\]:\s*(.*)/s);
    if (m) {
      defs[m[1]] = m[2].trim();
      defParas.push(p);
    }
  });
  if (Object.keys(defs).length === 0) return;
  var refCount = 0;
  var refMap = {};
  function processNode(node) {
    var walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
      acceptNode: function(n) {
        var p = n.parentNode;
        if (p.tagName === 'PRE' || p.tagName === 'CODE' || p.tagName === 'A') return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var textNodes = [];
    while (walker.nextNode()) textNodes.push(walker.currentNode);
    textNodes.forEach(function(tn) {
      var text = tn.textContent;
      if (text.indexOf('[^') === -1) return;
      var parts = text.split(/(\[\^[^\]]+\])/);
      if (parts.length <= 1) return;
      var frag = document.createDocumentFragment();
      parts.forEach(function(part) {
        var rm = part.match(/^\[\^([^\]]+)\]$/);
        if (rm && defs[rm[1]] !== undefined) {
          var id = rm[1];
          if (!refMap[id]) { refCount++; refMap[id] = refCount; }
          var num = refMap[id];
          var sup = document.createElement('sup');
          sup.className = 'footnote-ref';
          var a = document.createElement('a');
          a.href = '#fn-' + id;
          a.id = 'fnref-' + id;
          a.textContent = num;
          sup.appendChild(a);
          frag.appendChild(sup);
        } else {
          frag.appendChild(document.createTextNode(part));
        }
      });
      tn.parentNode.replaceChild(frag, tn);
    });
  }
  processNode(body);
  defParas.forEach(function(p) { p.remove(); });
  var section = document.createElement('section');
  section.className = 'footnotes';
  var hr = document.createElement('hr');
  section.appendChild(hr);
  var ol = document.createElement('ol');
  var keys = Object.keys(refMap).sort(function(a, b) { return refMap[a] - refMap[b]; });
  keys.forEach(function(id) {
    var li = document.createElement('li');
    li.id = 'fn-' + id;
    var textSpan = document.createElement('span');
    textSpan.textContent = defs[id] + ' ';
    li.appendChild(textSpan);
    var backref = document.createElement('a');
    backref.href = '#fnref-' + id;
    backref.className = 'footnote-backref';
    backref.textContent = '\u21A9';
    li.appendChild(backref);
    ol.appendChild(li);
  });
  section.appendChild(ol);
  body.appendChild(section);
  };
  __setupFootnotes();
})();
