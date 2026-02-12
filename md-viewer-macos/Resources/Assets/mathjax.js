window.MathJax = window.MathJax || {
  tex: {
    inlineMath: [['$', '$'], ['\\(', '\\)']],
    displayMath: [['$$', '$$'], ['\\[', '\\]']]
  },
  startup: {
    typeset: false
  },
  typesetPromise: function () {
    return Promise.resolve();
  }
};
