(function() {
  window.__setTheme = function(theme) {
    var html = document.documentElement;
    html.setAttribute('data-theme', theme);
    if (theme === 'dark') { html.style.colorScheme = 'dark'; }
    else if (theme === 'light') { html.style.colorScheme = 'light'; }
    else { html.style.colorScheme = ''; }
  };
})();
