/*!
 * standalone.js
 * Detects ?standalone=1 in the URL and hides the Shiny dashboard chrome
 * (header, sidebar, footer) so only the requested utility panel is visible.
 * Auto-opens the panel specified by ?panel=<name>.
 * Also handles ?rfcad_standalone=1 to pop out the RF CAD tool tab.
 */
(function () {
  'use strict';

  var params       = new URLSearchParams(window.location.search);
  var isStandalone = params.get('standalone') === '1' || params.get('rfcad_standalone') === '1';
  var panel        = params.get('panel');
  var rfcadMode    = params.get('rfcad_standalone') === '1';

  if (!isStandalone && !panel) return;

  // ── Inject CSS immediately (before paint) ─────────────────────────────
  if (isStandalone) {
    var style = document.createElement('style');
    style.id  = 'rfcad-standalone-css';
    style.textContent = [
      /* Hide Shiny/AdminLTE chrome */
      '.main-header, .main-sidebar, .control-sidebar,',
      '.content-wrapper > .content-header, body > .wrapper > .main-footer { display: none !important; }',
      /* Expand content to full viewport */
      '.content-wrapper { margin-left: 0 !important; padding: 0 !important; min-height: 100vh !important; }',
      'body, .wrapper { overflow: hidden; background: #0f0f1a !important; }',
    ].join('\n');

    if (!rfcadMode) {
      /* Utility drawer fills the entire window in non-rfcad standalone */
      style.textContent += [
        '#utility-drawer {',
        '  position: fixed !important; inset: 0 !important;',
        '  width: 100vw !important; height: 100vh !important;',
        '  transform: translateY(0) !important;',
        '  display: flex !important; flex-direction: column !important;',
        '  border-radius: 0 !important;',
        '}',
        '#utility-drawer.collapsed { display: flex !important; }',
        '#utility-drawer-body { flex: 1 1 auto; overflow: auto; }',
        '#drawer-full-btn, #drawer-close-btn { display: none !important; }',
      ].join('\n');
    }

    var inject = function () {
      (document.head || document.documentElement).appendChild(style);
    };
    if (document.head) { inject(); }
    else { document.addEventListener('DOMContentLoaded', inject); }
  }

  // ── Auto-open utility drawer panel ────────────────────────────────────
  if (panel && !rfcadMode) {
    var opened   = false;
    var attempts = 0;
    var tryOpen = function () {
      attempts++;
      if (opened || attempts > 60) return;
      if (typeof utilityDrawerOpen === 'function') {
        opened = true;
        utilityDrawerOpen(panel);
      } else {
        setTimeout(tryOpen, 250);
      }
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { setTimeout(tryOpen, 400); });
    } else {
      setTimeout(tryOpen, 400);
    }
  }

  // ── Auto-navigate to RF CAD tab ───────────────────────────────────────
  if (rfcadMode) {
    var navigated = false;
    var tryNav = function () {
      if (navigated) return;
      // Look for "RF CAD" tab link in Bootstrap nav pills / tabs
      var candidates = document.querySelectorAll('.nav a, .nav button, [role="tab"]');
      for (var i = 0; i < candidates.length; i++) {
        if (/rf\s*cad/i.test(candidates[i].textContent)) {
          navigated = true;
          candidates[i].click();
          return;
        }
      }
      // Fallback: Shiny tabsetPanel by data-value
      var byVal = document.querySelector('[data-value*="rf_cad"], [data-value*="rfcad"]');
      if (byVal) { navigated = true; byVal.click(); return; }
      setTimeout(tryNav, 300);
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { setTimeout(tryNav, 600); });
    } else {
      setTimeout(tryNav, 600);
    }
  }
})();
