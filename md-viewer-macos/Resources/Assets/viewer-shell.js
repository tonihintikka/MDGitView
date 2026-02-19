(function () {
  var root = document.body;
  if (!root) {
    return;
  }

  var enableMermaid = root.dataset.enableMermaid === 'true';
  var enableMath = root.dataset.enableMath === 'true';

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function getDiagramSize(svg) {
    if (svg.viewBox && svg.viewBox.baseVal && svg.viewBox.baseVal.width > 0 && svg.viewBox.baseVal.height > 0) {
      return {
        width: svg.viewBox.baseVal.width,
        height: svg.viewBox.baseVal.height
      };
    }

    var widthAttr = parseFloat(svg.getAttribute('width') || '');
    var heightAttr = parseFloat(svg.getAttribute('height') || '');
    if (widthAttr > 0 && heightAttr > 0) {
      return { width: widthAttr, height: heightAttr };
    }

    try {
      var bbox = svg.getBBox();
      if (bbox.width > 0 && bbox.height > 0) {
        return { width: bbox.width, height: bbox.height };
      }
    } catch (_error) {
      // Ignore browsers that disallow getBBox for hidden content.
    }

    var rect = svg.getBoundingClientRect();
    return {
      width: rect.width || 1,
      height: rect.height || 1
    };
  }

  function preferredViewportHeight(diagramHeight) {
    var minHeight = 220;
    var maxHeight = Math.max(minHeight, Math.floor((window.innerHeight || 900) * 0.72));
    return clamp(Math.ceil(diagramHeight + 24), minHeight, maxHeight);
  }

  function createControlButton(label, action, title, extraClass) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'mermaid-control-button' + (extraClass ? ' ' + extraClass : '');
    button.dataset.action = action;
    button.title = title;
    button.setAttribute('aria-label', title);
    button.textContent = label;
    return button;
  }

  function enableMermaidInteractions() {
    var diagrams = document.querySelectorAll('.mermaid[data-processed="true"]');
    diagrams.forEach(function (diagram) {
      if (diagram.dataset.interactiveReady === 'true') {
        return;
      }

      var svg = diagram.querySelector('svg');
      if (!svg) {
        return;
      }

      diagram.dataset.interactiveReady = 'true';
      diagram.classList.add('mermaid-interactive');

      var viewport = document.createElement('div');
      viewport.className = 'mermaid-viewport';
      svg.parentElement.insertBefore(viewport, svg);
      viewport.appendChild(svg);

      var controlLayer = document.createElement('div');
      controlLayer.className = 'mermaid-control-layer';

      var topRow = document.createElement('div');
      topRow.className = 'mermaid-control-top';
      topRow.appendChild(createControlButton('Fit', 'fit', 'Fit to viewport', 'mermaid-control-fit'));
      topRow.appendChild(createControlButton('Reset', 'reset', 'Reset view', 'mermaid-control-reset'));

      var pad = document.createElement('div');
      pad.className = 'mermaid-control-pad';
      pad.appendChild(createControlButton('Up', 'up', 'Pan up', 'mermaid-control-up'));
      pad.appendChild(createControlButton('Left', 'left', 'Pan left', 'mermaid-control-left'));
      pad.appendChild(createControlButton('Right', 'right', 'Pan right', 'mermaid-control-right'));
      pad.appendChild(createControlButton('Down', 'down', 'Pan down', 'mermaid-control-down'));
      pad.appendChild(createControlButton('+', 'zoomIn', 'Zoom in', 'mermaid-control-zoom-in'));
      pad.appendChild(createControlButton('-', 'zoomOut', 'Zoom out', 'mermaid-control-zoom-out'));

      controlLayer.appendChild(topRow);
      controlLayer.appendChild(pad);
      diagram.appendChild(controlLayer);

      var diagramSize = getDiagramSize(svg);
      viewport.style.height = preferredViewportHeight(diagramSize.height) + 'px';

      var state = {
        scale: 1,
        tx: 0,
        ty: 0,
        minScale: 0.2,
        maxScale: 6,
        panStep: 80
      };
      var viewMode = 'fit';

      function applyTransform() {
        svg.style.transform = 'translate(' + state.tx + 'px, ' + state.ty + 'px) scale(' + state.scale + ')';
      }

      function centerAtScale(scale) {
        var bounds = viewport.getBoundingClientRect();
        state.scale = clamp(scale, state.minScale, state.maxScale);
        state.tx = (bounds.width - diagramSize.width * state.scale) / 2;
        state.ty = (bounds.height - diagramSize.height * state.scale) / 2;
        applyTransform();
      }

      function fitToViewport() {
        var bounds = viewport.getBoundingClientRect();
        if (!bounds.width || !bounds.height) {
          return;
        }

        var scale = Math.min(bounds.width / diagramSize.width, bounds.height / diagramSize.height);
        if (!isFinite(scale) || scale <= 0) {
          scale = 1;
        }

        viewMode = 'fit';
        centerAtScale(scale);
      }

      function resetView() {
        viewMode = 'reset';
        state.scale = 1;
        state.tx = 0;
        state.ty = 0;
        applyTransform();
      }

      function panBy(dx, dy) {
        viewMode = 'custom';
        state.tx += dx;
        state.ty += dy;
        applyTransform();
      }

      function zoomAt(factor, pointX, pointY) {
        var nextScale = clamp(state.scale * factor, state.minScale, state.maxScale);
        if (nextScale === state.scale) {
          return;
        }

        var originX = typeof pointX === 'number' ? pointX : viewport.clientWidth / 2;
        var originY = typeof pointY === 'number' ? pointY : viewport.clientHeight / 2;
        var worldX = (originX - state.tx) / state.scale;
        var worldY = (originY - state.ty) / state.scale;

        viewMode = 'custom';
        state.scale = nextScale;
        state.tx = originX - worldX * state.scale;
        state.ty = originY - worldY * state.scale;
        applyTransform();
      }

      controlLayer.addEventListener('click', function (event) {
        var target = event.target;
        if (!(target instanceof HTMLButtonElement)) {
          return;
        }

        switch (target.dataset.action) {
          case 'fit':
            fitToViewport();
            break;
          case 'zoomIn':
            zoomAt(1.15);
            break;
          case 'zoomOut':
            zoomAt(1 / 1.15);
            break;
          case 'left':
            panBy(-state.panStep, 0);
            break;
          case 'right':
            panBy(state.panStep, 0);
            break;
          case 'up':
            panBy(0, -state.panStep);
            break;
          case 'down':
            panBy(0, state.panStep);
            break;
          case 'reset':
            resetView();
            break;
          default:
            break;
        }
      });

      viewport.addEventListener('wheel', function (event) {
        event.preventDefault();
        var bounds = viewport.getBoundingClientRect();
        var cursorX = event.clientX - bounds.left;
        var cursorY = event.clientY - bounds.top;
        zoomAt(event.deltaY < 0 ? 1.1 : 0.9, cursorX, cursorY);
      }, { passive: false });

      var isDragging = false;
      var lastX = 0;
      var lastY = 0;

      viewport.addEventListener('pointerdown', function (event) {
        if (event.button !== 0) {
          return;
        }

        isDragging = true;
        lastX = event.clientX;
        lastY = event.clientY;
        viewport.classList.add('is-dragging');
        viewport.setPointerCapture(event.pointerId);
      });

      viewport.addEventListener('pointermove', function (event) {
        if (!isDragging) {
          return;
        }

        var dx = event.clientX - lastX;
        var dy = event.clientY - lastY;
        lastX = event.clientX;
        lastY = event.clientY;
        panBy(dx, dy);
      });

      function endDragging(event) {
        if (!isDragging) {
          return;
        }

        isDragging = false;
        viewport.classList.remove('is-dragging');
        if (viewport.hasPointerCapture(event.pointerId)) {
          viewport.releasePointerCapture(event.pointerId);
        }
      }

      viewport.addEventListener('pointerup', endDragging);
      viewport.addEventListener('pointercancel', endDragging);

      window.addEventListener('resize', function () {
        viewport.style.height = preferredViewportHeight(diagramSize.height) + 'px';
        if (viewMode === 'fit') {
          fitToViewport();
          return;
        }
        applyTransform();
      });

      fitToViewport();
    });
  }

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
      Promise.resolve(window.mermaid.run({ querySelector: '.mermaid' })).then(function () {
        enableMermaidInteractions();
      }).catch(function () {
        Promise.resolve(window.mermaid.run()).then(function () {
          enableMermaidInteractions();
        }).catch(function () {
          // Keep Mermaid source visible as fallback.
        });
      });
      return;
    }

    if (typeof window.mermaid.init === 'function') {
      try {
        window.mermaid.init(undefined, mermaidNodes);
        enableMermaidInteractions();
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
