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

    /* Utility drawer fills the entire window in all standalone modes */
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
        // If ?rfcad=1 is also set, auto-click the RF CAD tab inside the drawer
        if (params.get('rfcad') === '1') {
          var tabAttempts = 0;
          var tryRfcadTab = function () {
            tabAttempts++;
            if (tabAttempts > 30) return;
            var tabs = document.querySelectorAll('.nav-tabs a, .nav-pills a, [role="tab"]');
            for (var i = 0; i < tabs.length; i++) {
              if (/rf\s*cad/i.test(tabs[i].textContent)) {
                tabs[i].click();
                return;
              }
            }
            setTimeout(tryRfcadTab, 500);
          };
          setTimeout(tryRfcadTab, 1000);
        }
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

  // ── Auto-navigate: open rf_tools drawer and click RF CAD tab ──────────────
  if (rfcadMode) {
    // RF CAD lives inside the utility drawer (rf_tools panel), not the main nav.
    // Open the drawer first, then poll for the RF CAD Bootstrap tab link.
    var openedRfcad = false, rfcadTabDone = false, rfcadOpenAttempts = 0;
    var tryOpenRfTools = function () {
      rfcadOpenAttempts++;
      if (openedRfcad || rfcadOpenAttempts > 40) return;
      if (typeof utilityDrawerOpen === 'function') {
        openedRfcad = true;
        utilityDrawerOpen('rf_tools');
        var tabAttempts = 0;
        var tryClickRfcadTab = function () {
          tabAttempts++;
          if (rfcadTabDone || tabAttempts > 30) return;
          var tabs = document.querySelectorAll('.nav-tabs a, .nav-pills a, [role="tab"]');
          for (var i = 0; i < tabs.length; i++) {
            if (/rf\s*cad/i.test(tabs[i].textContent)) {
              rfcadTabDone = true;
              tabs[i].click();
              return;
            }
          }
          setTimeout(tryClickRfcadTab, 500);
        };
        setTimeout(tryClickRfcadTab, 1000); // allow Shiny to render drawer content
      } else {
        setTimeout(tryOpenRfTools, 250);
      }
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { setTimeout(tryOpenRfTools, 400); });
    } else {
      setTimeout(tryOpenRfTools, 400);
    }
  }
})();
