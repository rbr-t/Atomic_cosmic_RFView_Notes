(function () {
  "use strict";

  let requestId = 0;
  let metadata = {};
  let extraFields = {};
  let suppressSnapshots = false;
  let lastSnapshot = "";
  let lastRequest = 0;
  let activeSlot = "1";
  let slots = {};

  function storeSlot() {
    const current = canvas();
    const zoom = d3.zoomTransform(current.svg.node());
    slots[activeSlot] = {
      document: snapshot(),
      history: JSON.parse(JSON.stringify(current.history)),
      historyIndex: current.historyIndex,
      nextId: current.nextId,
      zoom: { x: zoom.x, y: zoom.y, k: zoom.k }
    };
  }

  function workspaceSnapshot() {
    storeSlot();
    const canvases = {};
    for (const id of ["1", "2", "3", "4"]) {
      canvases[id] = slots[id]?.document || { schema_version: "1.0", components: [], connections: [], metadata: {} };
    }
    return { format: "rfview-workspace-v1", active: activeSlot, canvases };
  }

  function switchSlot(id) {
    if (!["1", "2", "3", "4"].includes(id)) throw new Error("Unknown canvas slot.");
    if (id === activeSlot) return;
    storeSlot();
    activeSlot = id;
    const saved = slots[id];
    restore(saved?.document || { schema_version: "1.0", components: [], connections: [], metadata: {} });
    const current = canvas();
    if (saved && saved.history.length) {
      current.history = JSON.parse(JSON.stringify(saved.history));
      current.historyIndex = saved.historyIndex;
      current.nextId = saved.nextId;
    }
    const zoom = saved?.zoom || { x: 0, y: 0, k: 1 };
    current.svg.call(current.zoom.transform, d3.zoomIdentity.translate(zoom.x, zoom.y).scale(zoom.k));
    Shiny.setInputValue("lineup_selected_component", null, { priority: "event" });
    Shiny.setInputValue("python_slot_changed", { slot: id, request_id: ++requestId }, { priority: "event" });
  }

  function reportError(error) {
    console.error("Python canvas adapter:", error);
    Shiny.setInputValue("python_canvas_error", String(error.message || error), { priority: "event" });
  }

  function canvas() {
    if (!window.paCanvas) throw new Error("Canvas is not ready. Refresh or check browser assets.");
    return window.paCanvas;
  }

  function snapshot() {
    const current = canvas();
    return JSON.parse(JSON.stringify({
      ...extraFields,
      schema_version: "1.0",
      components: current.components,
      connections: current.connections,
      metadata: metadata
    }));
  }

  function emitSnapshot() {
    if (suppressSnapshots || !window.paCanvas) return;
    const documentState = snapshot();
    const serialized = JSON.stringify(documentState);
    if (serialized === lastSnapshot) return;
    lastSnapshot = serialized;
    Shiny.setInputValue("python_snapshot", documentState, { priority: "event" });
  }

  function action(name) {
    const current = canvas();
    emitSnapshot();
    lastRequest = ++requestId;
    Shiny.setInputValue("python_action", {
      action: name, document: snapshot(), request_id: lastRequest,
      workspace: name === "workspace_snapshot" ? workspaceSnapshot() : null
    }, { priority: "event" });
    return current;
  }

  function restore(documentState) {
    const current = canvas();
    suppressSnapshots = true;
    try {
      const copy = JSON.parse(JSON.stringify(documentState));
      metadata = copy.metadata || {};
      extraFields = { ...copy };
      delete extraFields.components;
      delete extraFields.connections;
      delete extraFields.metadata;
      current.selectedComponent = null;
      current.selectedComponents = [];
      current.selectedConnection = null;
      const numericIds = copy.components.filter(c => typeof c.id === "number").map(c => c.id);
      current.restoreState({
        components: copy.components, connections: copy.connections,
        nextId: Math.max(0, ...numericIds) + 1
      });
      current.instructionText.style("display", copy.components.length ? "none" : "block");
      current.history = [];
      current.historyIndex = -1;
      current.saveHistory();
      current.drawGuideLines();
      lastSnapshot = "";
      lastRequest = ++requestId;
    } finally {
      suppressSnapshots = false;
    }
    emitSnapshot();
  }

  function initialize() {
    try {
      if (!window.initializePACanvas()) throw new Error("Legacy D3 canvas initialization failed.");
      const current = canvas();
      if (!current._pythonAdapterReady) {
        for (const method of ["saveHistory", "restoreState"]) {
          const original = current[method].bind(current);
          current[method] = function (...args) {
            const result = original(...args);
            // Some legacy methods update connections immediately after saving history.
            queueMicrotask(emitSnapshot);
            return result;
          };
        }
        current._pythonAdapterReady = true;
      }
      Shiny.addCustomMessageHandler("pythonLoadConfiguration", data => {
        try { restore(data); } catch (error) { reportError(error); }
      });
      Shiny.addCustomMessageHandler("pythonLoadWorkspace", data => {
        try {
          slots = {};
          for (const [id, documentState] of Object.entries(data.canvases)) {
            slots[id] = { document: documentState, history: [], historyIndex: -1, zoom: { x: 0, y: 0, k: 1 } };
          }
          activeSlot = data.active;
          document.getElementById("python_canvas_slot").value = activeSlot;
          document.getElementById("python_canvas_slot").dispatchEvent(new Event("change", { bubbles: true }));
          restore(slots[activeSlot].document);
          canvas().svg.call(canvas().zoom.transform, d3.zoomIdentity);
        } catch (error) { reportError(error); }
      });
      Shiny.addCustomMessageHandler("pythonEditComponent", data => {
        try {
          const target = canvas().components.find(c => c.id === data.id);
          if (!target) throw new Error("Selected component no longer exists.");
          target.properties = { ...target.properties, ...data.properties };
          if (target.type === "transistor") {
            for (const key of ["pout_p3db", "pout_pavg", "pin_p3db", "pin_pavg",
              "pae_p3db", "pae_pavg"]) delete target.properties[key];
          }
          canvas().restoreState({
            components: canvas().components, connections: canvas().connections,
            nextId: canvas().nextId
          });
          canvas().saveHistory();
          emitSnapshot();
        } catch (error) { reportError(error); }
      });
      Shiny.addCustomMessageHandler("pythonResults", data => {
        if (data.request_id !== lastRequest) return;
        // Do not overwrite legacy model inputs with computed outputs.
        // The authoritative Python results are displayed in the result panel.
        canvas().pythonResults = data.stages;
      });
      Shiny.setInputValue("python_canvas_ready", ++requestId, { priority: "event" });
    } catch (error) { reportError(error); }
  }

  document.addEventListener("click", event => {
    const button = event.target.closest("button");
    if (!button || !button.id.startsWith("python_")) return;
    try {
      switch (button.id) {
        case "python_calculate": action("calculate"); break;
        case "python_snapshot": action("snapshot"); break;
        case "python_workspace_snapshot": action("workspace_snapshot"); break;
        case "python_add": canvas().addComponent("transistor", 220, 250); break;
        case "python_wire": canvas().toggleWireMode(); break;
        case "python_undo": canvas().undo(); emitSnapshot(); break;
        case "python_redo": canvas().redo(); emitSnapshot(); break;
      }
    } catch (error) { reportError(error); }
  });

  document.addEventListener("change", event => {
    if (event.target.id !== "python_canvas_slot") return;
    try { switchSlot(event.target.value); } catch (error) { reportError(error); }
  });

  // The R canvas emits inputs while initializing. Python requires the session
  // init handshake to finish before accepting those input messages.
  $(document).one("shiny:sessioninitialized", function () {
    const registerHandler = Shiny.addCustomMessageHandler;
    // The retained R canvas registers this no-payload handler with zero arguments;
    // Python's Shiny client requires exactly one. Limit the shim to script loading.
    Shiny.addCustomMessageHandler = function (name, handler) {
      if (name === "reinit_sticky" && handler.length === 0) {
        return registerHandler(name, function (data) { handler(data); });
      }
      return registerHandler(name, handler);
    };
    const script = document.createElement("script");
    script.src = "legacy/pa_lineup_canvas.js";
    script.onload = () => {
      Shiny.addCustomMessageHandler = registerHandler;
      initialize();
    };
    script.onerror = () => {
      Shiny.addCustomMessageHandler = registerHandler;
      reportError(new Error("Could not load the retained lineup canvas."));
    };
    document.head.appendChild(script);
  });
}());
