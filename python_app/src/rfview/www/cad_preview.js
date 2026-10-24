(function () {
  "use strict";

  function selectCadComponent(target) {
    const component = target.closest(".cad-layout-component[data-cad-id]");
    if (!component || typeof Shiny === "undefined") return false;
    Shiny.setInputValue("cad_preview_select", component.dataset.cadId, { priority: "event" });
    return true;
  }

  document.addEventListener("click", event => {
    if (event.target instanceof Element) selectCadComponent(event.target);
  });

  document.addEventListener("keydown", event => {
    if (!(event.target instanceof Element)) return;
    if (event.key !== "Enter" && event.key !== " ") return;
    if (selectCadComponent(event.target)) event.preventDefault();
  });
})();
