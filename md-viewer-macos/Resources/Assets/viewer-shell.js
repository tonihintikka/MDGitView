(function () {
  var root = document.body;
  if (!root) {
    return;
  }

  var enableMermaid = root.dataset.enableMermaid === 'true';
  var enableMath = root.dataset.enableMath === 'true';

  function normalizeMermaidBlocks() {
    var codeBlocks = document.querySelectorAll('pre > code.language-mermaid');
    codeBlocks.forEach(function (code) {
      var pre = code.parentElement;
      if (!pre || !pre.parentElement) {
        return;
      }

      var container = document.createElement('div');
      container.className = 'mermaid';
      // textContent decodes HTML entities from code nodes into plain Mermaid source.
      container.textContent = code.textContent || '';
      pre.parentElement.replaceChild(container, pre);
    });
  }

  function renderMermaid() {
    if (!enableMermaid || !window.mermaid) {
      return;
    }

    normalizeMermaidBlocks();
    var isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: isDark ? 'dark' : 'default'
    });

    var mermaidNodes = document.querySelectorAll('.mermaid');
    if (!mermaidNodes.length) {
      return;
    }

    if (typeof window.mermaid.run === 'function') {
      Promise.resolve(window.mermaid.run({ querySelector: '.mermaid' })).catch(function () {
        Promise.resolve(window.mermaid.run()).catch(function () {
          // Keep Mermaid source visible as fallback.
        });
      });
      return;
    }

    if (typeof window.mermaid.init === 'function') {
      try {
        window.mermaid.init(undefined, mermaidNodes);
      } catch (_error) {
        // Keep Mermaid source visible as fallback.
      }
    }
  }

  renderMermaid();

  if (enableMath && window.MathJax && typeof window.MathJax.typesetPromise === 'function') {
    window.MathJax.typesetPromise().catch(function () {
      // Keep raw math text visible as fallback.
    });
  }
})();
