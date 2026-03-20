(function() {
  if (!window.renderMathInElement) return;
  try {
    renderMathInElement(document.body, {
      output: 'mathml',
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '$', right: '$', display: false },
        { left: '\\(', right: '\\)', display: false },
        { left: '\\[', right: '\\]', display: true }
      ],
      throwOnError: false
    });
  } catch(e) {}
})();
