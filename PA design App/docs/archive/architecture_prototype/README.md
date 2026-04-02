# Architecture prototype

This folder contains a small editable prototype for the PA Design app architecture.

- `index.html`: single-file prototype with a left-hand editable 2D layer panel and a 3D view (Three.js) on the right. Click a 3D layer to select it in the panel. Edit names inline and export the configuration as JSON.

How to use:

1. Open `index.html` in a browser (double-click or serve via a simple HTTP server).
2. Edit layer names directly in the left panel.
3. Click a layer in the 3D view to highlight the matching panel item.
4. Use "Export JSON" to save the current architecture.

Notes:

- This is a lightweight prototype to capture the requested editable 2D + 3D visualization. We can extend it to support persistent storage, annotations, layer metadata (tags), and integration with R/Shiny or MCP tools as the next step.
