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

  function getDiagramBounds(svg) {
    if (svg.viewBox && svg.viewBox.baseVal && svg.viewBox.baseVal.width > 0 && svg.viewBox.baseVal.height > 0) {
      return {
        x: svg.viewBox.baseVal.x || 0,
        y: svg.viewBox.baseVal.y || 0,
        width: svg.viewBox.baseVal.width,
        height: svg.viewBox.baseVal.height
      };
    }

    var viewBoxAttr = svg.getAttribute('viewBox');
    if (viewBoxAttr) {
      var parts = viewBoxAttr.trim().split(/\s+/).map(function (part) { return parseFloat(part); });
      if (parts.length === 4 && isFinite(parts[2]) && isFinite(parts[3]) && parts[2] > 0 && parts[3] > 0) {
        return {
          x: isFinite(parts[0]) ? parts[0] : 0,
          y: isFinite(parts[1]) ? parts[1] : 0,
          width: parts[2],
          height: parts[3]
        };
      }
    }

    var widthAttr = parseFloat(svg.getAttribute('width') || '');
    var heightAttr = parseFloat(svg.getAttribute('height') || '');
    if (widthAttr > 0 && heightAttr > 0) {
      return { x: 0, y: 0, width: widthAttr, height: heightAttr };
    }

    try {
      var bbox = svg.getBBox();
      if (bbox.width > 0 && bbox.height > 0) {
        return {
          x: bbox.x || 0,
          y: bbox.y || 0,
          width: bbox.width,
          height: bbox.height
        };
      }
    } catch (_error) {
      // Ignore browsers that disallow getBBox for hidden content.
    }

    var rect = svg.getBoundingClientRect();
    return {
      x: 0,
      y: 0,
      width: rect.width || 1,
      height: rect.height || 1
    };
  }

  function preferredViewportHeight(diagramHeight) {
    var minHeight = 220;
    var maxHeight = 500;
    return Math.min(maxHeight, Math.max(minHeight, Math.ceil(diagramHeight + 24)));
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
      var launcherRow = document.createElement('div');
      launcherRow.className = 'mermaid-control-launcher';
      var toolsToggleButton = createControlButton('Tools', 'toggleTools', 'Show tools', 'mermaid-control-tools-toggle');
      launcherRow.appendChild(toolsToggleButton);

      var topRow = document.createElement('div');
      topRow.className = 'mermaid-control-top';
      topRow.appendChild(createControlButton('Fit', 'fit', 'Fit to viewport', 'mermaid-control-fit'));
      topRow.appendChild(createControlButton('Reset', 'reset', 'Reset view', 'mermaid-control-reset'));
      var wheelToggleButton = createControlButton('Wheel', 'toggleWheel', 'Enable wheel zoom', 'mermaid-control-wheel');
      topRow.appendChild(wheelToggleButton);

      var pad = document.createElement('div');
      pad.className = 'mermaid-control-pad';
      pad.appendChild(createControlButton('Up', 'up', 'Pan up', 'mermaid-control-up'));
      pad.appendChild(createControlButton('Left', 'left', 'Pan left', 'mermaid-control-left'));
      pad.appendChild(createControlButton('Right', 'right', 'Pan right', 'mermaid-control-right'));
      pad.appendChild(createControlButton('Down', 'down', 'Pan down', 'mermaid-control-down'));
      pad.appendChild(createControlButton('+', 'zoomIn', 'Zoom in', 'mermaid-control-zoom-in'));
      pad.appendChild(createControlButton('-', 'zoomOut', 'Zoom out', 'mermaid-control-zoom-out'));

      var panel = document.createElement('div');
      panel.className = 'mermaid-control-panel';
      panel.appendChild(topRow);
      panel.appendChild(pad);

      controlLayer.appendChild(launcherRow);
      controlLayer.appendChild(panel);
      diagram.appendChild(controlLayer);

      var diagramBounds = getDiagramBounds(svg);
      // Save mermaid's original style (e.g. "max-width: 800px;") to restore when tools close.
      var svgOriginalStyle = svg.getAttribute('style') || '';
      var svgOriginalWidth = svg.getAttribute('width') || '';
      var svgOriginalHeight = svg.getAttribute('height') || '';

      var state = {
        scale: 1,
        tx: 0,
        ty: 0,
        minScale: 0.2,
        maxScale: 6,
        panStep: 80,
        wheelZoomEnabled: false,
        toolsEnabled: false
      };
      var viewMode = 'fit';
      var fitPadding = 18;
      var isDragging = false;
      var lastX = 0;
      var lastY = 0;

      function refreshDiagramBounds() {
        diagramBounds = getDiagramBounds(svg);
      }

      function stopDragging(pointerId) {
        if (!isDragging) {
          return;
        }

        isDragging = false;
        viewport.classList.remove('is-dragging');
        if (typeof pointerId === 'number' && viewport.hasPointerCapture(pointerId)) {
          viewport.releasePointerCapture(pointerId);
        }
      }

      function updateWheelToggleUI() {
        wheelToggleButton.classList.toggle('is-active', state.wheelZoomEnabled);
        var title = state.wheelZoomEnabled ? 'Disable wheel zoom' : 'Enable wheel zoom';
        wheelToggleButton.title = title;
        wheelToggleButton.setAttribute('aria-label', title);
      }

      function updateToolsUI() {
        controlLayer.classList.toggle('is-expanded', state.toolsEnabled);
        diagram.classList.toggle('mermaid-tools-enabled', state.toolsEnabled);
        toolsToggleButton.classList.toggle('is-active', state.toolsEnabled);
        var title = state.toolsEnabled ? 'Hide tools' : 'Show tools';
        toolsToggleButton.title = title;
        toolsToggleButton.setAttribute('aria-label', title);

        if (state.toolsEnabled) {
          // Activate viewport mode: replace mermaid's responsive style with fixed pixel size
          refreshDiagramBounds();
          svg.removeAttribute('style');
          svg.setAttribute('width', diagramBounds.width + 'px');
          svg.setAttribute('height', diagramBounds.height + 'px');
          viewport.style.height = preferredViewportHeight(diagramBounds.height) + 'px';
          requestAnimationFrame(function () {
            requestAnimationFrame(function () {
              fitToViewport();
            });
          });
        } else {
          // Deactivate: restore mermaid's original attributes, remove transform
          svg.setAttribute('style', svgOriginalStyle);
          svg.setAttribute('width', svgOriginalWidth);
          svg.setAttribute('height', svgOriginalHeight);
          if (!svgOriginalStyle) { svg.removeAttribute('style'); }
          if (!svgOriginalWidth) { svg.removeAttribute('width'); }
          if (!svgOriginalHeight) { svg.removeAttribute('height'); }
          viewport.style.height = '';
          svg.style.transform = '';
          state.scale = 1; state.tx = 0; state.ty = 0;
          viewMode = 'fit';
          state.wheelZoomEnabled = false;
          updateWheelToggleUI();
          stopDragging();
        }
      }

      function applyTransform() {
        svg.style.transform = 'translate(' + state.tx + 'px, ' + state.ty + 'px) scale(' + state.scale + ')';
      }

      function centerAtScale(scale) {
        var bounds = viewport.getBoundingClientRect();
        state.scale = clamp(scale, state.minScale, state.maxScale);
        state.tx = (bounds.width - diagramBounds.width * state.scale) / 2 - diagramBounds.x * state.scale;
        state.ty = (bounds.height - diagramBounds.height * state.scale) / 2 - diagramBounds.y * state.scale;
        applyTransform();
      }

      function fitToViewport() {
        var bounds = viewport.getBoundingClientRect();
        if (!bounds.width || !bounds.height) {
          return;
        }

        refreshDiagramBounds();
        var usableWidth = Math.max(1, bounds.width - fitPadding * 2);
        var usableHeight = Math.max(1, bounds.height - fitPadding * 2);
        var scale = Math.min(usableWidth / diagramBounds.width, usableHeight / diagramBounds.height);
        if (!isFinite(scale) || scale <= 0) {
          scale = 1;
        }

        viewMode = 'fit';
        centerAtScale(scale);
      }

      function resetView() {
        fitToViewport();
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

        if (!state.toolsEnabled && target.dataset.action !== 'toggleTools') {
          return;
        }

        switch (target.dataset.action) {
          case 'toggleTools':
            state.toolsEnabled = !state.toolsEnabled;
            updateToolsUI();
            break;
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
          case 'toggleWheel':
            state.wheelZoomEnabled = !state.wheelZoomEnabled;
            updateWheelToggleUI();
            break;
          default:
            break;
        }
      });

      viewport.addEventListener('wheel', function (event) {
        if (!state.toolsEnabled || !state.wheelZoomEnabled) {
          return;
        }
        event.preventDefault();
        var bounds = viewport.getBoundingClientRect();
        var cursorX = event.clientX - bounds.left;
        var cursorY = event.clientY - bounds.top;
        zoomAt(event.deltaY < 0 ? 1.1 : 0.9, cursorX, cursorY);
      }, { passive: false });

      viewport.addEventListener('pointerdown', function (event) {
        if (!state.toolsEnabled || event.button !== 0) {
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
        stopDragging(event.pointerId);
      }

      viewport.addEventListener('pointerup', endDragging);
      viewport.addEventListener('pointercancel', endDragging);

      window.addEventListener('resize', function () {
        refreshDiagramBounds();
        viewport.style.height = preferredViewportHeight(diagramBounds.height) + 'px';
        if (viewMode === 'fit') {
          fitToViewport();
          return;
        }
        applyTransform();
      });

      updateWheelToggleUI();
      updateToolsUI();
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
