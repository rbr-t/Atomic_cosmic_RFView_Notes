// =============================================================================
// utility_drawer.js
// Right-side sliding drawer for the PA Design App utility bar.
//
// Loaded as a static file — no R string escaping, plain JavaScript.
// All functions are top-level declarations (automatically global scope).
// =============================================================================

var _drawerTab = null;
var _splitContrastActive = false;
var _drawerPinned = false;
var _utilityStateKey = "pa_utility_bar_state_v1";
var _restoringUtilityState = false;
var _panelSessionVersion = "v1";

var _drawerMeta = {
  util_data:      { title: "Data Manager"      },
  rf_calc:        { title: "RF Calculators"    },
  rf_tools:       { title: "RF Tools"          },
  util_agents:    { title: "AI Agents"         },
  util_knowledge: { title: "Knowledge Base"    },
  settings:       { title: "Settings"          }
};

var _drawerPanelToTab = {
  util_data: "projects",
  rf_calc: "sys_freq_planning",
  rf_tools: "fp_tlines",
  util_agents: "dashboard",
  util_knowledge: "tech_device_lib",
  settings: "settings"
};

function utilityCurrentProjectKey() {
  // Use the selected project when available; otherwise keep a global fallback scope.
  var projectSelect = document.getElementById("calc_project_select");
  if (projectSelect && projectSelect.value && String(projectSelect.value).trim().length) {
    return String(projectSelect.value).trim();
  }
  return "global";
}

function utilityPanelSessionKey(panel) {
  return ["pa_utility_panel_session", _panelSessionVersion, utilityCurrentProjectKey(), panel || "none"].join("::");
}

function utilityReadPanelSession(panel) {
  if (!panel) return null;
  try {
    var raw = localStorage.getItem(utilityPanelSessionKey(panel));
    if (!raw) return null;
    var parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch (e) {
    return null;
  }
}

function utilityWritePanelSession(panel, payload) {
  if (!panel || !payload) return;
  try {
    localStorage.setItem(utilityPanelSessionKey(panel), JSON.stringify(payload));
  } catch (e) {
    // Ignore storage failures in restricted modes.
  }
}

function utilityCaptureActiveTabs(root) {
  var out = {};
  if (!root) return out;
  var tabSets = root.querySelectorAll(".nav-tabs");
  for (var i = 0; i < tabSets.length; i++) {
    var nav = tabSets[i];
    var active = nav.querySelector("li.active a[data-toggle='tab']");
    if (!active) continue;
    var href = active.getAttribute("href");
    if (!href) continue;
    var navId = nav.id && nav.id.length ? nav.id : ("idx_" + i);
    out[navId] = href;
  }
  return out;
}

function utilityRestoreActiveTabs(root, tabsState) {
  if (!root || !tabsState || typeof tabsState !== "object") return;
  Object.keys(tabsState).forEach(function(navId) {
    var href = tabsState[navId];
    if (!href) return;
    var scope = root;
    if (navId.indexOf("idx_") !== 0) {
      var byId = root.querySelector("#" + navId);
      if (byId) scope = byId;
    }
    var link = scope.querySelector("a[data-toggle='tab'][href='" + href + "']") ||
               root.querySelector("a[data-toggle='tab'][href='" + href + "']");
    if (!link) return;
    if (typeof $ !== "undefined" && $.fn && $.fn.tab) {
      try { $(link).tab("show"); } catch (e) { link.click(); }
    } else {
      link.click();
    }
  });
}

function utilityCapturePanelControls(root) {
  var values = {};
  if (!root) return values;

  var fields = root.querySelectorAll("input[id], select[id], textarea[id]");
  for (var i = 0; i < fields.length; i++) {
    var el = fields[i];
    if (!el || !el.id) continue;
    if (el.type === "file") continue;

    if (el.type === "checkbox" || el.type === "radio") {
      values[el.id] = !!el.checked;
    } else {
      values[el.id] = el.value;
    }
  }

  return values;
}

function utilityRestorePanelControls(root, controlState) {
  if (!root || !controlState || typeof controlState !== "object") return;

  Object.keys(controlState).forEach(function(id) {
    var el = document.getElementById(id);
    if (!el || !root.contains(el)) return;

    var next = controlState[id];
    if (el.type === "checkbox" || el.type === "radio") {
      el.checked = !!next;
      el.dispatchEvent(new Event("change", { bubbles: true }));
      return;
    }

    if (next === null || typeof next === "undefined") return;
    el.value = String(next);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  });
}

function utilityFilterRelayoutPayload(evtData) {
  var out = {};
  if (!evtData || typeof evtData !== "object") return out;
  Object.keys(evtData).forEach(function(k) {
    if (k.indexOf("range") >= 0 || k.indexOf("autorange") >= 0) {
      out[k] = evtData[k];
    }
  });
  return out;
}

function utilityBindPlotlyRelayoutCapture(panel) {
  if (!panel) return;
  var root = document.getElementById("utility-drawer-body");
  if (!root) return;

  var plots = root.querySelectorAll(".js-plotly-plot[id]");
  for (var i = 0; i < plots.length; i++) {
    var plot = plots[i];
    if (!plot || !plot.id) continue;
    if (plot.dataset.utilityRelayoutBound === "1") continue;
    if (typeof plot.on !== "function") continue;

    plot.dataset.utilityRelayoutBound = "1";
    plot.on("plotly_relayout", (function(plotId) {
      return function(evtData) {
        var current = utilityReadPanelSession(panel) || {};
        current.controls = current.controls || utilityCapturePanelControls(root);
        current.tabs = current.tabs || utilityCaptureActiveTabs(root);
        current.plotly = current.plotly || {};
        current.plotly[plotId] = utilityFilterRelayoutPayload(evtData);
        current.updatedAt = Date.now();
        utilityWritePanelSession(panel, current);
      };
    })(plot.id));
  }
}

function utilityRestorePlotlyState(root, plotlyState) {
  if (!root || !plotlyState || typeof plotlyState !== "object") return;
  Object.keys(plotlyState).forEach(function(plotId) {
    var payload = plotlyState[plotId];
    if (!payload || typeof payload !== "object") return;
    var plot = document.getElementById(plotId);
    if (!plot || !root.contains(plot)) return;
    if (typeof Plotly === "undefined" || typeof Plotly.relayout !== "function") return;
    if (!Object.keys(payload).length) return;
    try { Plotly.relayout(plot, payload); } catch (e) {}
  });
}

function utilitySaveActivePanelSession() {
  if (!_drawerTab) return;
  var root = document.getElementById("utility-drawer-body");
  if (!root) return;
  var payload = {
    controls: utilityCapturePanelControls(root),
    tabs: utilityCaptureActiveTabs(root),
    plotly: (utilityReadPanelSession(_drawerTab) || {}).plotly || {},
    updatedAt: Date.now()
  };
  utilityWritePanelSession(_drawerTab, payload);
}

function utilityRestorePanelSession(panel, attempt) {
  if (!panel) return;
  var root = document.getElementById("utility-drawer-body");
  if (!root) return;

  var maxAttempts = 10;
  var n = typeof attempt === "number" ? attempt : 0;

  // Wait for dynamic Shiny UI to be injected before restoring.
  if (!root.children || root.children.length === 0) {
    if (n < maxAttempts) {
      setTimeout(function() { utilityRestorePanelSession(panel, n + 1); }, 120);
    }
    return;
  }

  var sessionState = utilityReadPanelSession(panel);
  if (!sessionState) {
    utilityBindPlotlyRelayoutCapture(panel);
    return;
  }

  utilityRestorePanelControls(root, sessionState.controls);
  utilityRestoreActiveTabs(root, sessionState.tabs);
  utilityBindPlotlyRelayoutCapture(panel);

  // Restore plot ranges after controls/tabs settle.
  setTimeout(function() {
    utilityRestorePlotlyState(root, sessionState.plotly);
  }, 180);
}

function utilityPersistState() {
  if (_restoringUtilityState) return;
  try {
    var drawer = document.getElementById("utility-drawer");
    var expandBtn = document.getElementById("drawer-full-btn");
    var state = {
      tab: _drawerTab,
      open: !!(drawer && drawer.classList.contains("open")),
      pinned: !!_drawerPinned,
      expandState: (expandBtn && expandBtn.getAttribute("data-expand-state")) || "75",
      transparent: !!(drawer && drawer.classList.contains("drawer-transparent")),
      portalMain: !!(drawer && drawer.classList.contains("drawer-portal-main")),
      transparencyLevel: (document.getElementById("drawer-transparency-level") || {}).value || "0.50",
      splitContrast: !!_splitContrastActive,
      mainTheme: utilityCurrentThemeMode(),
      drawerTheme: drawer && drawer.classList.contains("drawer-theme-light") ? "light" : "dark",
      headerTheme: document.body.classList.contains("utility-header-theme-light") ? "light" : "dark"
    };
    localStorage.setItem(_utilityStateKey, JSON.stringify(state));
  } catch (e) {
    // Ignore localStorage errors in restricted browser modes.
  }
}

function utilityRestoreState() {
  _restoringUtilityState = true;
  try {
    var raw = localStorage.getItem(_utilityStateKey);
    if (!raw) {
      _restoringUtilityState = false;
      return false;
    }
    var state = JSON.parse(raw);
    if (!state || typeof state !== "object") {
      _restoringUtilityState = false;
      return false;
    }

    _drawerPinned = !!state.pinned;
    var pinBtn = document.getElementById("drawer-pin-btn");
    if (pinBtn) {
      pinBtn.classList.toggle("active", _drawerPinned);
      pinBtn.innerHTML = _drawerPinned
        ? '<i class="fa fa-thumb-tack"></i> Unpin'
        : '<i class="fa fa-thumb-tack"></i> Pin';
    }

    var level = document.getElementById("drawer-transparency-level");
    if (level && state.transparencyLevel) level.value = state.transparencyLevel;
    utilityDrawerSetTransparencyLevel((level && level.value) || "0.50");

    if (state.mainTheme === "light" || state.mainTheme === "dark") {
      utilityApplyThemeMode(state.mainTheme);
      utilitySyncThemeInputs(state.mainTheme);
    }

    if (state.splitContrast) {
      _splitContrastActive = true;
      utilitySetDrawerTheme(state.drawerTheme === "light" ? "light" : "dark");
      utilitySetHeaderTheme(state.headerTheme === "light" ? "light" : "dark");
    }

    var drawer = document.getElementById("utility-drawer");
    if (drawer) {
      // Restore expand state (50%, 75%, 95%)
      var expandState = state.expandState || "75";
      drawer.classList.remove("drawer-expand-50", "drawer-expand-75", "drawer-expand-95", "drawer-full");
      drawer.classList.add("drawer-expand-" + expandState);
      var expandBtn = document.getElementById("drawer-full-btn");
      if (expandBtn) {
        expandBtn.setAttribute("data-expand-state", expandState);
        var expandLabels = { "50": "50%", "75": "75%", "95": "95%" };
        expandBtn.innerHTML = '<i class="fa fa-arrows-alt-h"></i> ' + (expandLabels[expandState] || "75%");
      }

      drawer.classList.toggle("drawer-transparent", !!state.transparent);
      drawer.classList.toggle("drawer-portal-main", !!state.portalMain);
    }

    var tbtn = document.getElementById("drawer-transparency-btn");
    if (tbtn) {
      tbtn.classList.toggle("active", !!state.transparent);
      tbtn.innerHTML = state.transparent
        ? '<i class="fa fa-adjust"></i> Solid'
        : '<i class="fa fa-adjust"></i> Transparent';
    }

    if (level) level.disabled = !state.transparent;

    var portalBtn = document.getElementById("drawer-portal-btn");
    if (portalBtn) {
      portalBtn.classList.toggle("active", !!state.portalMain);
      portalBtn.innerHTML = state.portalMain
        ? '<i class="fa fa-mouse-pointer"></i> Portal: Main'
        : '<i class="fa fa-mouse-pointer"></i> Portal: Utility';
    }

    if (state.open && state.tab) {
      _drawerTab = null;
      utilityDrawerOpen(state.tab);
    }

    _restoringUtilityState = false;
    return true;
  } catch (e) {
    // Ignore invalid persisted state.
    _restoringUtilityState = false;
    return false;
  }
}

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

  // Restore panel UI session (controls/sub-tabs/plot ranges) per project.
  setTimeout(function() {
    utilityRestorePanelSession(tabName, 0);
  }, 60);

  utilityPersistState();
}

function utilityDrawerClose() {
  utilitySaveActivePanelSession();
  var drawer = document.getElementById("utility-drawer");
  if (drawer) {
    drawer.classList.remove("open");
    drawer.classList.remove("drawer-full");  // reset expand state on close
    drawer.classList.remove("drawer-portal-main");
  }
  document.querySelectorAll(".utility-nav").forEach(function(el) {
    el.classList.remove("active-utility");
  });
  _drawerTab = null;
  utilityPersistState();
}

function utilityDrawerTogglePin() {
  _drawerPinned = !_drawerPinned;
  var btn = document.getElementById("drawer-pin-btn");
  if (btn) {
    btn.classList.toggle("active", _drawerPinned);
    btn.innerHTML = _drawerPinned
      ? '<i class="fa fa-thumb-tack"></i> Unpin'
      : '<i class="fa fa-thumb-tack"></i> Pin';
    btn.title = _drawerPinned
      ? "Unpin utility drawer (restore auto-minimize)"
      : "Pin utility drawer (disable auto-minimize)";
  }

  utilityPersistState();
}

function utilityDrawerToggleTransparency() {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;
  var isTransparent = drawer.classList.toggle("drawer-transparent");
  if (!isTransparent) drawer.classList.remove("drawer-portal-main");
  var btn = document.getElementById("drawer-transparency-btn");
  var portalBtn = document.getElementById("drawer-portal-btn");
  var level = document.getElementById("drawer-transparency-level");
  if (btn) {
    btn.classList.toggle("active", isTransparent);
    btn.innerHTML = isTransparent
      ? '<i class="fa fa-adjust"></i> Solid'
      : '<i class="fa fa-adjust"></i> Transparent';
  }
  if (portalBtn && !isTransparent) {
    portalBtn.classList.remove("active");
    portalBtn.innerHTML = '<i class="fa fa-mouse-pointer"></i> Portal: Utility';
  }
  if (level) level.disabled = !isTransparent;

  if (isTransparent) {
    utilityApplySplitContrastTheme(true);
  } else {
    utilityClearSplitContrastTheme();
  }

  utilityPersistState();
}

function utilityDrawerSetTransparencyLevel(transparency) {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;

  // transparency: 0.80 means 80% transparent => alpha 0.20 (more see-through).
  var t = parseFloat(transparency);
  if (!isFinite(t) || t < 0 || t >= 1) return;
  var alpha = 1 - t;
  drawer.style.setProperty("--drawer-alpha", String(alpha));
  utilityPersistState();
}

function utilitySetDrawerTheme(mode) {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;
  drawer.classList.remove("drawer-theme-light", "drawer-theme-dark");
  drawer.classList.add(mode === "light" ? "drawer-theme-light" : "drawer-theme-dark");
}

function utilitySetHeaderTheme(mode) {
  document.body.classList.remove("utility-header-theme-light", "utility-header-theme-dark");
  document.body.classList.add(mode === "light" ? "utility-header-theme-light" : "utility-header-theme-dark");
}

function utilityApplySplitContrastTheme(togglePair) {
  var mainMode = utilityCurrentThemeMode();
  if (togglePair) mainMode = mainMode === "light" ? "dark" : "light";

  var utilityMode = mainMode === "light" ? "dark" : "light";
  _splitContrastActive = true;

  utilityApplyThemeMode(mainMode);
  utilitySyncThemeInputs(mainMode);
  utilitySetDrawerTheme(utilityMode);
  utilitySetHeaderTheme(utilityMode);
  utilityPersistState();
}

function utilityClearSplitContrastTheme() {
  _splitContrastActive = false;
  var drawer = document.getElementById("utility-drawer");
  if (drawer) drawer.classList.remove("drawer-theme-light", "drawer-theme-dark");
  document.body.classList.remove("utility-header-theme-light", "utility-header-theme-dark");
  utilityPersistState();
}

function utilityDrawerTogglePortalMode() {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;

  // Portal action always enables transparency and snaps to 80% transparency.
  if (!drawer.classList.contains("drawer-transparent")) {
    drawer.classList.add("drawer-transparent");
    var tbtn = document.getElementById("drawer-transparency-btn");
    if (tbtn) {
      tbtn.classList.add("active");
      tbtn.innerHTML = '<i class="fa fa-adjust"></i> Solid';
    }
  }

  var level = document.getElementById("drawer-transparency-level");
  if (level) {
    level.disabled = false;
    level.value = "0.80";
  }
  utilityDrawerSetTransparencyLevel("0.80");

  // Flip pair each portal click so utility and main remain visually opposite.
  utilityApplySplitContrastTheme(true);

  var mainMode = drawer.classList.toggle("drawer-portal-main");
  var portalBtn = document.getElementById("drawer-portal-btn");
  if (portalBtn) {
    portalBtn.classList.toggle("active", mainMode);
    portalBtn.innerHTML = mainMode
      ? '<i class="fa fa-mouse-pointer"></i> Portal: Main'
      : '<i class="fa fa-mouse-pointer"></i> Portal: Utility';
  }

  utilityPersistState();
}

function utilityCurrentThemeMode() {
  if (document.body.classList.contains("theme-light")) return "light";
  return "dark";
}

function utilityApplyThemeMode(themeMode) {
  document.body.classList.remove("theme-light", "theme-colorblind");
  if (themeMode === "light") document.body.classList.add("theme-light");

  var nextMode = themeMode === "light" ? "dark" : "light";
  var iconClass = nextMode === "light" ? "fa fa-sun-o" : "fa fa-moon";
  var main = document.getElementById("utility-theme-toggle-main");
  var drawerBtn = document.getElementById("drawer-theme-toggle-btn");

  if (main) {
    main.innerHTML = '<i class="' + iconClass + '"></i> ' + (nextMode === "light" ? "Light" : "Dark");
  }
  if (drawerBtn) {
    drawerBtn.innerHTML = '<i class="' + iconClass + '"></i> ' + (nextMode === "light" ? "Light" : "Dark");
  }

  utilityPersistState();
}

function utilitySyncThemeInputs(themeMode) {
  // Keep UI selectors in sync without firing recursive change chains.
  var themeSelect = document.getElementById("theme_select");
  if (themeSelect) themeSelect.value = themeMode;
  var drawerThemeSelect = document.getElementById("drawer_theme_select");
  if (drawerThemeSelect) drawerThemeSelect.value = themeMode;

  // Notify Shiny directly (if available) instead of synthetic DOM change events.
  if (typeof Shiny !== "undefined" && Shiny.setInputValue) {
    Shiny.setInputValue("theme_select", themeMode, { priority: "event" });
    Shiny.setInputValue("drawer_theme_select", themeMode, { priority: "event" });
  }
}

function utilityToggleThemeShortcut() {
  if (_splitContrastActive) {
    utilityApplySplitContrastTheme(true);
    return;
  }

  var nextMode = utilityCurrentThemeMode() === "light" ? "dark" : "light";
  utilityApplyThemeMode(nextMode);
  utilitySyncThemeInputs(nextMode);
}

// Cycle through expansion widths: 75vw → 95vw → 50vw → 75vw (repeat)
function utilityDrawerCycleExpand() {
  var drawer = document.getElementById("utility-drawer");
  if (!drawer) return;
  var btn = document.getElementById("drawer-full-btn");
  if (!btn) return;

  // Get current state from data attribute
  var currentState = btn.getAttribute("data-expand-state") || "75";
  var nextState, nextWidth, nextLabel;

  switch(currentState) {
    case "50":
      nextState = "75";
      nextLabel = "75%";
      break;
    case "75":
      nextState = "95";
      nextLabel = "95%";
      break;
    case "95":
      nextState = "50";
      nextLabel = "50%";
      break;
    default:
      nextState = "75";
      nextLabel = "75%";
  }

  // Update data attribute and button text
  btn.setAttribute("data-expand-state", nextState);
  btn.innerHTML = '<i class="fa fa-arrows-alt-h"></i> ' + nextLabel;

  // Remove all width classes and add the new one
  drawer.classList.remove("drawer-expand-50", "drawer-expand-75", "drawer-expand-95", "drawer-full");
  drawer.classList.add("drawer-expand-" + nextState);

  utilityPersistState();
}

// Toggle between 75 vw (default) and full-width (100 vw − sidebar) modes.
// DEPRECATED: Use utilityDrawerCycleExpand() instead
function utilityDrawerToggleFull() {
  utilityDrawerCycleExpand();
}

// Open the utility drawer in a new standalone browser window
function utilityDrawerPopout() {
  if (!_drawerTab) return;
  var panelId = encodeURIComponent(_drawerTab);
  var base = window.location.href.split("?")[0].split("#")[0];
  
  // Create URL with drawer=1 parameter to trigger standalone drawer rendering
  var url = base + "?drawer=" + panelId + "&standalone=1&draweronly=1";
  
  window.open(
    url,
    "_blank",
    "width=800,height=600,menubar=no,toolbar=no,location=no,status=no,resizable=yes"
  );
}

// Navigate to the closest full-page tab for the active drawer panel.
function utilityDrawerFullView() {
  if (!_drawerTab) return;
  var tabName = _drawerPanelToTab[_drawerTab];
  if (tabName && typeof Shiny !== "undefined" && Shiny.setInputValue) {
    Shiny.setInputValue("goto_utility_tab", tabName, { priority: "event" });
  }
  utilityDrawerClose();
}

// Detect standalone drawer mode and set up layout accordingly
function detectStandaloneDrawerMode() {
  var urlParams = new URLSearchParams(window.location.search);
  var drawerParam = urlParams.get("drawer");
  var drawerOnlyMode = urlParams.get("draweronly");
  
  if (drawerOnlyMode === "1" && drawerParam) {
    // Hide all main UI elements except the drawer
    document.body.classList.add("drawer-standalone-mode");
    
    // Hide header, sidebar, main content area
    var header = document.querySelector(".main-header");
    if (header) header.style.display = "none";
    
    var sidebar = document.querySelector(".left-side");
    if (sidebar) sidebar.style.display = "none";
    
    var contentWrapper = document.querySelector(".content-wrapper");
    if (contentWrapper) {
      contentWrapper.style.display = "none";
    }
    
    // Show and position the drawer
    var drawer = document.getElementById("utility-drawer");
    if (drawer) {
      drawer.classList.add("open", "drawer-expand-75");
      drawer.classList.remove("drawer-expand-50", "drawer-expand-95");
      drawer.style.right = "0";
      drawer.style.width = "100vw";
      drawer.style.position = "fixed";
    }
    
    // Set drawer tab from URL parameter
    _drawerTab = drawerParam;
    var meta = _drawerMeta[drawerParam] || { title: drawerParam };
    var titleEl = document.getElementById("utility-drawer-title");
    if (titleEl) titleEl.textContent = meta.title;
    
    // Render drawer content immediately if Shiny is available
    if (typeof Shiny !== "undefined" && Shiny.setInputValue) {
      Shiny.setInputValue("utility_drawer_tab", drawerParam, { priority: "event" });
    }
  }
}

// -----------------------------------------------------------------------------
// Wire everything up once the DOM is ready
// -----------------------------------------------------------------------------
$(document).ready(function() {
  
  // Detect and set up standalone drawer mode first
  detectStandaloneDrawerMode();

  // Utility bar link clicks (delegated — works even if DOM is mutated by Shiny)
  $(document).on("click", ".utility-link", function(e) {
    e.preventDefault();
    e.stopPropagation();
    var panel = $(this).data("panel");
    if (panel) utilityDrawerOpen(panel);
    return false;
  });

  // Drawer header button clicks
  $(document).on("click", "#drawer-pin-btn", function(e) { e.stopPropagation(); utilityDrawerTogglePin(); });
  $(document).on("click", "#drawer-full-btn",   function(e) { e.stopPropagation(); utilityDrawerToggleFull(); });
  $(document).on("click", "#drawer-transparency-btn", function(e) { e.stopPropagation(); utilityDrawerToggleTransparency(); });
  $(document).on("click", "#drawer-portal-btn", function(e) { e.stopPropagation(); utilityDrawerTogglePortalMode(); });
  $(document).on("change", "#drawer-transparency-level", function() {
    utilityDrawerSetTransparencyLevel(this.value);
  });
  $(document).on("click", "#drawer-theme-toggle-btn, #utility-theme-toggle-main", function(e) {
    e.preventDefault();
    e.stopPropagation();
    utilityToggleThemeShortcut();
    return false;
  });
  $(document).on("click", "#drawer-popout-btn", function(e) { e.stopPropagation(); utilityDrawerPopout();  });
  $(document).on("click", "#drawer-close-btn",  function(e) { e.stopPropagation(); utilityDrawerClose();   });

  // Persist utility panel form state while the user is working.
  $(document).on("input change", "#utility-drawer-body input[id], #utility-drawer-body select[id], #utility-drawer-body textarea[id]", function() {
    utilitySaveActivePanelSession();
  });

  // Project switch: keep previous project's session and restore the new project's session.
  $(document).on("change", "#calc_project_select", function() {
    utilitySaveActivePanelSession();
    if (_drawerTab) {
      setTimeout(function() {
        utilityRestorePanelSession(_drawerTab, 0);
      }, 80);
    }
  });

  // Click anywhere outside the drawer (and not on a utility link) closes it
  $(document).on("click", function(e) {
    if (_drawerTab === null) return;
    if (_drawerPinned) return;
    if ($(e.target).closest("#utility-drawer").length) return;
    if ($(e.target).closest(".utility-nav").length) return;
    utilityDrawerClose();
  });

  // Inject "TOOLS" label before the first utility-nav item
  var $first = $(".utility-nav").first();
  if ($first.length && !$("#utility-nav-label").length) {
    $first.before('<li class="dropdown"><span class="utility-nav-label" id="utility-nav-label">Tools</span></li>');
  }

  var restored = utilityRestoreState();
  if (!restored) {
    utilityDrawerSetTransparencyLevel($("#drawer-transparency-level").val() || "0.50");
    $("#drawer-transparency-level").prop("disabled", true);
    $("#drawer-pin-btn").removeClass("active").html('<i class="fa fa-thumb-tack"></i> Pin');

    // Keep shortcut labels coherent when the theme is changed from settings.
    utilityApplyThemeMode(utilityCurrentThemeMode());
  }
  $(document).on("change", "#theme_select, #drawer_theme_select", function() {
    var selectedMode = ((this && this.value) === "light") ? "light" : "dark";
    utilityApplyThemeMode(selectedMode);
    if (_splitContrastActive) {
      var utilityMode = selectedMode === "light" ? "dark" : "light";
      utilitySetDrawerTheme(utilityMode);
      utilitySetHeaderTheme(utilityMode);
    }
    utilityPersistState();
  });
});
