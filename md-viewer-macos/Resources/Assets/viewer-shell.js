(function () {
  var root = document.body;
  var enableMermaid = root.dataset.enableMermaid === 'true';
  var enableMath = root.dataset.enableMath === 'true';

  if (enableMermaid && window.mermaid) {
    window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
    if (typeof window.mermaid.run === 'function') {
      window.mermaid.run();
    }
  }

  if (enableMath && window.MathJax && typeof window.MathJax.typesetPromise === 'function') {
    window.MathJax.typesetPromise().catch(function () {
      // Keep raw math text visible as fallback.
    });
  }
})();
