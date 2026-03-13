// =============================================================================
// utility_drawer.js
// Right-side sliding drawer for the PA Design App utility bar.
//
// Loaded as a static file — no R string escaping, plain JavaScript.
// All functions are top-level declarations (automatically global scope).
// =============================================================================

var _drawerTab = null;

var _drawerMeta = {
  util_data:      { title: "Data Manager"      },
  rf_calc:        { title: "RF Calculators"    },
  rf_tools:       { title: "RF Tools"          },
  util_agents:    { title: "AI Agents"         },
  util_knowledge: { title: "Knowledge Base"    },
  settings:       { title: "Settings"          }
};

// Open (or toggle closed) the drawer for a given panel name.
function utilityDrawerOpen(tabName) {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;

  // Second click on same panel closes it
  if (_drawerTab === tabName && drawer.classList.contains("open")) {
    utilityDrawerClose();
    return;
  }

  _drawerTab = tabName;

  // Update title
  var meta = _drawerMeta[tabName] || { title: tabName };
  var titleEl = document.getElementById("utility-drawer-title");
  if (titleEl) titleEl.textContent = meta.title;

  // Open drawer
  drawer.classList.add("open");

  // Highlight the clicked utility-nav item
  document.querySelectorAll(".utility-nav").forEach(function(el) {
    el.classList.remove("active-utility");
  });
  var link = document.querySelector('[data-panel="' + tabName + '"]');
  if (link) {
    var li = link.closest(".utility-nav");
    if (li) li.classList.add("active-utility");
  }

  // Tell Shiny to render drawer content
  if (typeof Shiny !== "undefined" && Shiny.setInputValue) {
    Shiny.setInputValue("utility_drawer_tab", tabName, { priority: "event" });
  }
}

function utilityDrawerClose() {
  var drawer = document.getElementById("utility-drawer");
  if (drawer) {
    drawer.classList.remove("open");
    drawer.classList.remove("drawer-full");  // reset expand state on close
  }
  document.querySelectorAll(".utility-nav").forEach(function(el) {
    el.classList.remove("active-utility");
  });
  _drawerTab = null;
}

// Toggle between 75 vw (default) and full-width (100 vw − sidebar) modes.
function utilityDrawerToggleFull() {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;
  var isExpanded = drawer.classList.toggle("drawer-full");
  var btn = document.getElementById("drawer-full-btn");
  if (btn) btn.textContent = isExpanded ? "\u25c4 Collapse" : "\u25ba Expand";
}

// Open the full app in a new browser tab with ?panel= pre-selected.
function utilityDrawerPopout() {
  if (!_drawerTab) return;
  var base = window.location.href.split("?")[0].split("#")[0];
  window.open(base + "?panel=" + encodeURIComponent(_drawerTab), "_blank");
}

// -----------------------------------------------------------------------------
// Wire everything up once the DOM is ready
// -----------------------------------------------------------------------------
$(document).ready(function() {

  // Utility bar link clicks (delegated — works even if DOM is mutated by Shiny)
  $(document).on("click", ".utility-link", function(e) {
    e.preventDefault();
    e.stopPropagation();
    var panel = $(this).data("panel");
    if (panel) utilityDrawerOpen(panel);
    return false;
  });

  // Drawer header button clicks
  $(document).on("click", "#drawer-full-btn",   function(e) { e.stopPropagation(); utilityDrawerToggleFull(); });
  $(document).on("click", "#drawer-popout-btn", function(e) { e.stopPropagation(); utilityDrawerPopout();  });
  $(document).on("click", "#drawer-close-btn",  function(e) { e.stopPropagation(); utilityDrawerClose();   });

  // Click anywhere outside the drawer (and not on a utility link) closes it
  $(document).on("click", function(e) {
    if (_drawerTab === null) return;
    if ($(e.target).closest("#utility-drawer").length) return;
    if ($(e.target).closest(".utility-nav").length) return;
    utilityDrawerClose();
  });

  // Inject "TOOLS" label before the first utility-nav item
  var $first = $(".utility-nav").first();
  if ($first.length && !$("#utility-nav-label").length) {
    $first.before('<li class="dropdown"><span class="utility-nav-label" id="utility-nav-label">Tools</span></li>');
  }
});
