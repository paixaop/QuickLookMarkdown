(function() {
  window.__setupFrontmatter = function() {
    // Remove existing banner before rebuilding
    var existingBanner = document.querySelector('.frontmatter-banner');
    if (existingBanner) existingBanner.remove();
  var el = document.getElementById('frontmatter-data');
  if (!el) return;
  var raw = el.textContent;
  if (!raw || !window.jsyaml) return;
  try {
    var data = jsyaml.load(raw);
    if (!data || typeof data !== 'object') return;
    var banner = document.createElement('div');
    banner.className = 'frontmatter-banner';
    if (data.title) {
      var t = document.createElement('div');
      t.className = 'frontmatter-title';
      t.textContent = data.title;
      banner.appendChild(t);
    }
    var meta = [];
    if (data.author) meta.push(data.author);
    if (data.date) meta.push(String(data.date));
    if (meta.length > 0) {
      var m = document.createElement('div');
      m.className = 'frontmatter-meta';
      m.textContent = meta.join(' \u00B7 ');
      banner.appendChild(m);
    }
    if (data.tags && Array.isArray(data.tags)) {
      var tagsDiv = document.createElement('div');
      tagsDiv.className = 'frontmatter-tags';
      data.tags.forEach(function(tag) {
        var pill = document.createElement('span');
        pill.className = 'frontmatter-tag';
        pill.textContent = tag;
        tagsDiv.appendChild(pill);
      });
      banner.appendChild(tagsDiv);
    }
    var body = document.querySelector('.markdown-body');
    if (body) {
      var stats = body.querySelector('.reading-stats');
      if (stats) body.insertBefore(banner, stats);
      else body.insertBefore(banner, body.firstChild);
    }
  } catch(e) {}
  };
  __setupFrontmatter();
})();
