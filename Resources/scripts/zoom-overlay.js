(function() {
  var scale, panX, panY, overlay, content, zoomLabel, fitScale;
  var dragging = false, didDrag = false, startX, startY, startPanX, startPanY;
  function updateTransform() {
    content.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + scale + ')';
    if (zoomLabel) zoomLabel.textContent = Math.round(scale * 100) + '%';
  }
  function setScale(s) { scale = Math.min(Math.max(s, 0.1), 10); updateTransform(); }
  function closeOverlay() {
    if (overlay) { overlay.remove(); overlay = null; }
  }
  function fitToScreen() {
    if (!content || !overlay) return;
    var el = content.querySelector('svg') || content.querySelector('img');
    if (!el) return;
    var vw = overlay.clientWidth * 0.85, vh = overlay.clientHeight * 0.85;
    var sw, sh;
    if (el.tagName === 'IMG') { sw = el.naturalWidth || el.width; sh = el.naturalHeight || el.height; }
    else { sw = el.width.baseVal.value || el.getBoundingClientRect().width; sh = el.height.baseVal.value || el.getBoundingClientRect().height; }
    if (sw > 0 && sh > 0) { fitScale = Math.min(vw / (sw + 48), vh / (sh + 48), 3); }
    else { fitScale = 1; }
    scale = fitScale; panX = 0; panY = 0; updateTransform();
  }
  function openOverlay(cloneEl) {
    scale = 1; panX = 0; panY = 0; fitScale = 1;
    overlay = document.createElement('div');
    overlay.className = 'mermaid-overlay';
    var controls = document.createElement('div');
    controls.className = 'mermaid-overlay-controls';
    var btnPlus = document.createElement('button');
    btnPlus.textContent = '+';
    btnPlus.title = 'Zoom in (+)';
    btnPlus.addEventListener('click', function(ev) { ev.stopPropagation(); setScale(scale + 0.25); });
    var btnMinus = document.createElement('button');
    btnMinus.textContent = '\u2212';
    btnMinus.title = 'Zoom out (\u2212)';
    btnMinus.addEventListener('click', function(ev) { ev.stopPropagation(); setScale(scale - 0.25); });
    zoomLabel = document.createElement('span');
    zoomLabel.className = 'mermaid-overlay-zoom-label';
    zoomLabel.textContent = '100%';
    zoomLabel.title = 'Reset zoom';
    zoomLabel.addEventListener('click', function(ev) {
      ev.stopPropagation(); scale = 1; panX = 0; panY = 0; updateTransform();
    });
    var btnClose = document.createElement('button');
    btnClose.textContent = '\u00D7';
    btnClose.title = 'Close (Esc)';
    btnClose.addEventListener('click', function(ev) { ev.stopPropagation(); closeOverlay(); });
    controls.appendChild(btnPlus);
    controls.appendChild(btnMinus);
    controls.appendChild(zoomLabel);
    controls.appendChild(btnClose);
    content = document.createElement('div');
    content.className = 'mermaid-overlay-content';
    content.appendChild(cloneEl);
    content.addEventListener('click', function(ev) { ev.stopPropagation(); });
    content.addEventListener('dblclick', function(ev) {
      ev.stopPropagation();
      if (Math.abs(scale - 1) < 0.01 && panX === 0 && panY === 0) { fitToScreen(); }
      else { scale = 1; panX = 0; panY = 0; updateTransform(); }
    });
    content.addEventListener('mousedown', function(ev) {
      ev.preventDefault(); ev.stopPropagation();
      dragging = true; didDrag = false;
      startX = ev.clientX; startY = ev.clientY;
      startPanX = panX; startPanY = panY;
      content.style.cursor = 'grabbing';
    });
    var viewport = document.createElement('div');
    viewport.className = 'mermaid-overlay-viewport';
    viewport.appendChild(content);
    viewport.addEventListener('click', function(ev) { if (!didDrag) closeOverlay(); });
    overlay.appendChild(controls);
    overlay.appendChild(viewport);
    document.body.appendChild(overlay);
    setTimeout(fitToScreen, 50);
  }
  document.addEventListener('click', function(e) {
    var mermaidDiv = e.target.closest('.mermaid');
    if (mermaidDiv) {
      var svg = mermaidDiv.querySelector('svg');
      if (svg) openOverlay(svg.cloneNode(true));
      return;
    }
    var img = e.target.closest('.markdown-body img');
    if (img) {
      var clone = img.cloneNode(true);
      clone.style.maxWidth = '85vw';
      clone.style.maxHeight = '80vh';
      clone.style.display = 'block';
      openOverlay(clone);
    }
  });
  document.addEventListener('mousemove', function(e) {
    if (!dragging) return;
    var dx = e.clientX - startX, dy = e.clientY - startY;
    if (Math.abs(dx) > 3 || Math.abs(dy) > 3) didDrag = true;
    panX = startPanX + dx; panY = startPanY + dy;
    updateTransform();
  });
  document.addEventListener('mouseup', function() {
    if (dragging) { dragging = false; if (content) content.style.cursor = 'grab'; }
  });
  document.addEventListener('wheel', function(e) {
    if (!overlay) return;
    e.preventDefault();
    var delta = e.deltaY > 0 ? -0.1 : 0.1;
    var rect = overlay.getBoundingClientRect();
    var cx = e.clientX - rect.left - rect.width / 2;
    var cy = e.clientY - rect.top - rect.height / 2;
    var oldScale = scale;
    setScale(scale + delta);
    var ratio = scale / oldScale;
    panX = cx - ratio * (cx - panX); panY = cy - ratio * (cy - panY);
    updateTransform();
  }, { passive: false });
  document.addEventListener('keydown', function(e) {
    if (!overlay) return;
    var step = 40;
    if (e.key === 'Escape') { closeOverlay(); }
    else if (e.key === '+' || e.key === '=') { setScale(scale + 0.25); }
    else if (e.key === '-' || e.key === '_') { setScale(scale - 0.25); }
    else if (e.key === '0') { scale = 1; panX = 0; panY = 0; updateTransform(); }
    else if (e.key === 'ArrowLeft') { panX += step; updateTransform(); }
    else if (e.key === 'ArrowRight') { panX -= step; updateTransform(); }
    else if (e.key === 'ArrowUp') { panY += step; updateTransform(); }
    else if (e.key === 'ArrowDown') { panY -= step; updateTransform(); }
  });
})();
