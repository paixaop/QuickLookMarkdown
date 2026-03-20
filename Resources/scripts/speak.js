(function() {
  if (typeof speechSynthesis === 'undefined') return;
  var btn = document.createElement('button');
  btn.id = 'speak-btn';
  btn.innerHTML = '<svg width=\'14\' height=\'14\' viewBox=\'0 0 24 24\' fill=\'none\' stroke=\'currentColor\' stroke-width=\'2\' stroke-linecap=\'round\' stroke-linejoin=\'round\'><polygon points=\'11 5 6 9 2 9 2 15 6 15 11 19 11 5\'/><path d=\'M19.07 4.93a10 10 0 0 1 0 14.14\'/><path d=\'M15.54 8.46a5 5 0 0 1 0 7.07\'/></svg>';
  btn.title = 'Read aloud';
  var state = 'idle';
  function setState(s) {
    state = s;
    btn.classList.toggle('speaking', s === 'speaking');
    btn.classList.toggle('paused', s === 'paused');
    if (s === 'idle') btn.innerHTML = '<svg width=\'14\' height=\'14\' viewBox=\'0 0 24 24\' fill=\'none\' stroke=\'currentColor\' stroke-width=\'2\' stroke-linecap=\'round\' stroke-linejoin=\'round\'><polygon points=\'11 5 6 9 2 9 2 15 6 15 11 19 11 5\'/><path d=\'M19.07 4.93a10 10 0 0 1 0 14.14\'/><path d=\'M15.54 8.46a5 5 0 0 1 0 7.07\'/></svg>';
    else if (s === 'speaking') btn.innerHTML = '<svg width=\'14\' height=\'14\' viewBox=\'0 0 24 24\' fill=\'none\' stroke=\'currentColor\' stroke-width=\'2\' stroke-linecap=\'round\' stroke-linejoin=\'round\'><rect x=\'6\' y=\'4\' width=\'4\' height=\'16\'/><rect x=\'14\' y=\'4\' width=\'4\' height=\'16\'/></svg>';
    else if (s === 'paused') btn.innerHTML = '<svg width=\'14\' height=\'14\' viewBox=\'0 0 24 24\' fill=\'none\' stroke=\'currentColor\' stroke-width=\'2\' stroke-linecap=\'round\' stroke-linejoin=\'round\'><polygon points=\'5 3 19 12 5 21 5 3\'/></svg>';
  }
  function getText() {
    var body = document.querySelector('.markdown-body');
    return (body || document.body).textContent || '';
  }
  function stop() { speechSynthesis.cancel(); setState('idle'); }
  function start() {
    stop();
    var utt = new SpeechSynthesisUtterance(getText());
    utt.onend = function() { setState('idle'); };
    speechSynthesis.speak(utt);
    setState('speaking');
  }
  function pause() { speechSynthesis.pause(); setState('paused'); }
  function resume() { speechSynthesis.resume(); setState('speaking'); }
  var lastClick = 0;
  btn.addEventListener('click', function() {
    var now = Date.now();
    if (now - lastClick < 350) { stop(); lastClick = 0; return; }
    lastClick = now;
    setTimeout(function() {
      if (Date.now() - lastClick < 350) return;
      if (state === 'idle') start();
      else if (state === 'speaking') pause();
      else if (state === 'paused') resume();
    }, 360);
  });
  document.body.appendChild(btn);
  window.__speak = { start: start, pause: pause, resume: resume, stop: stop };
})();
