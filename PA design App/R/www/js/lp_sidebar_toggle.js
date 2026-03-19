/* ── LP Viewer sidebar collapse toggle ─────────────────────────────────────
   Clicking any .lp-sidebar-toggle-btn toggles the .row ancestor's
   .lp-sidebar-hidden class, which the CSS uses to hide col-sm-3 and
   expand col-sm-9 to full width.  A 250 ms timeout then fires a window
   resize event so Plotly reflows its plots to fill the wider area.
   ───────────────────────────────────────────────────────────────────────── */
$(document).ready(function () {
  $(document).on('click', '.lp-sidebar-toggle-btn', function () {
    $(this).closest('.row').toggleClass('lp-sidebar-hidden');
    /* trigger plotly / other widget reflow after the CSS transition */
    setTimeout(function () { $(window).trigger('resize'); }, 260);
  });
});
