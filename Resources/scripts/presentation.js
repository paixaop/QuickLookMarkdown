(function() {
  var overlay, slides, currentSlide, counter;
  function buildSlides() {
    var body = document.querySelector('.markdown-body');
    if (!body) return [];
    var children = Array.from(body.children);
    var result = [[]];
    children.forEach(function(el) {
      if (el.tagName === 'HR') { result.push([]); }
      else { result[result.length - 1].push(el); }
    });
    return result.filter(function(s) { return s.length > 0; });
  }
  function showSlide(n) {
    if (n < 0 || n >= slides.length) return;
    currentSlide = n;
    var content = overlay.querySelector('.pres-content');
    while (content.firstChild) content.removeChild(content.firstChild);
    slides[n].forEach(function(el) {
      content.appendChild(el.cloneNode(true));
    });
    counter.textContent = (n + 1) + ' / ' + slides.length;
  }
  function start() {
    slides = buildSlides();
    if (slides.length === 0) return;
    currentSlide = 0;
    overlay = document.createElement('div');
    overlay.className = 'pres-overlay';
    var content = document.createElement('div');
    content.className = 'pres-content';
    counter = document.createElement('div');
    counter.className = 'pres-counter';
    var closeBtn = document.createElement('button');
    closeBtn.className = 'pres-close';
    closeBtn.textContent = '\u00D7';
    closeBtn.addEventListener('click', stop);
    overlay.appendChild(content);
    overlay.appendChild(counter);
    overlay.appendChild(closeBtn);
    document.body.appendChild(overlay);
    showSlide(0);
  }
  function stop() {
    if (overlay) { overlay.remove(); overlay = null; }
  }
  function next() { if (overlay && currentSlide < slides.length - 1) showSlide(currentSlide + 1); }
  function prev() { if (overlay && currentSlide > 0) showSlide(currentSlide - 1); }
  document.addEventListener('keydown', function(e) {
    if (!overlay) return;
    if (e.key === 'Escape') { stop(); }
    else if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); next(); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); prev(); }
  });
  document.addEventListener('click', function(e) {
    if (!overlay) return;
    if (e.target === overlay || e.target.classList.contains('pres-content')) next();
  });
  window.__startPresentation = function() {
    if (overlay) { stop(); } else { start(); }
  };
  window.__stopPresentation = stop;
  window.__presentationActive = function() { return !!overlay; };
})();
