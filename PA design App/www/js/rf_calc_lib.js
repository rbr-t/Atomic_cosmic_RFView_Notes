/*!
 * rf_calc_lib.js — RF Engineering Formula Library
 * Phase 2: parametric microstrip calculations.
 *
 * All lengths in mm, frequencies in GHz, impedances in Ω.
 * Formulas: Hammerstad & Jensen (1980), Wheeler (1977), IPC-2141.
 *
 * Public namespace: window.rfCalc
 */
(function (global) {
  'use strict';

  const C0   = 299.792;      // speed of light  mm/ns  → λ(mm) = C0/f(GHz)/√εeff
  const ETA0 = 376.730;      // free-space wave impedance Ω
  const MU0  = 1.2566e-6;    // H/m  (for via inductance)

  // ── helpers ────────────────────────────────────────────────────────────
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

  // ── Microstrip Analysis ───────────────────────────────────────────────
  // Hammerstad & Jensen (1980) — accurate to <0.5% for 0.05 ≤ W/h ≤ 20
  // W, h, t  in mm;  er ≥ 1  (dimensionless);  freq_GHz optional
  // Returns: { Z0, eeff, lambda_g, theta_per_mm, alpha_c, alpha_d, Weff }
  function msAnalysis(W, h, er, t, freq_GHz, tanD) {
    if (W <= 0 || h <= 0 || er < 1) return null;
    t    = t    || 0;
    tanD = tanD || 0;

    // ── Effective width (Wheeler 1977 thickness correction) ──────────
    let Weff = W;
    if (t > 0 && t < h) {
      const u_t = W / h;
      const dW  = (t / Math.PI) *
        (1 + Math.log(u_t >= 1 / (2 * Math.PI) ? 2 * h / t : 4 * Math.E * W / (t * t)));
      Weff = W + clamp(dW, 0, W * 0.5);
    }

    const u  = Weff / h;
    const u2 = u * u;
    const u4 = u2 * u2;

    // ── εeff (Hammerstad & Jensen) ────────────────────────────────────
    const a = 1 +
      Math.log((u4 + Math.pow(u / 52, 2)) / (u4 + 0.432)) / 49 +
      Math.log(1 + Math.pow(u / 18.1, 3)) / 18.7;
    const b  = 0.564 * Math.pow(clamp((er - 0.9) / (er + 3), 1e-9, 10), 0.053);
    const eeff = (er + 1) / 2 + (er - 1) / 2 * Math.pow(1 + 10 / u, -a * b);

    // ── Z0 ────────────────────────────────────────────────────────────
    const F    = 6 + (2 * Math.PI - 6) * Math.exp(-Math.pow(30.666 / u, 0.7528));
    const Z0   = ETA0 / (2 * Math.PI * Math.sqrt(eeff)) *
      Math.log(F / u + Math.sqrt(1 + 4 / u2));

    // ── Frequency-dependent quantities ────────────────────────────────
    let lambda_g = null, theta_per_mm = null, alpha_c = null, alpha_d = null;

    if (freq_GHz && freq_GHz > 0) {
      lambda_g     = C0 / (freq_GHz * Math.sqrt(eeff));           // mm
      theta_per_mm = 360 / lambda_g;                              // °/mm

      // Conductor loss (Wheeler incremental inductance; Cu: ρ=1.724e-8 Ω·m)
      const f_Hz = freq_GHz * 1e9;
      const Rs   = Math.sqrt(Math.PI * f_Hz * 4e-7 * Math.PI * 1.724e-8); // Ω/sq
      const Rs_mm = Rs / 1000;  // Ω/sq → rough per-mm factor
      // alpha_c (dB/mm) — simplified Wheeler rule
      alpha_c = (8.686 * Rs_mm / (Z0 * Weff)) * 0.5;

      // Dielectric loss (Pozar 4.21)
      // α_d (dB/mm) = 27.3 * er/(er-1) * (eeff-1)/sqrt(eeff) * tanD / lambda_0
      const lambda_0 = C0 / freq_GHz;  // mm free-space
      alpha_d = (27.3 * er / (er - 1 || 0.001)) *
        ((eeff - 1) / Math.sqrt(eeff)) * tanD / lambda_0;
    }

    return { Z0, eeff, lambda_g, theta_per_mm, alpha_c, alpha_d, Weff };
  }

  // ── Microstrip Synthesis ──────────────────────────────────────────────
  // Wheeler (1977) — returns { W, eeff, Z0_check }
  function msSynthesis(Z0_target, h, er, t) {
    if (Z0_target <= 0 || h <= 0 || er < 1) return null;
    const A = (Z0_target / 60) * Math.sqrt((er + 1) / 2) +
      (er - 1) / (er + 1) * (0.23 + 0.11 / er);
    const uN = 8 * Math.exp(A) / (Math.exp(2 * A) - 2);

    let u;
    if (uN <= 2) {
      u = uN;
    } else {
      const B = 377 * Math.PI / (2 * Z0_target * Math.sqrt(er));
      const lnB = Math.log(2 * B - 1);
      u = (2 / Math.PI) * (B - 1 - lnB +
        (er - 1) / (2 * er) * (Math.log(B - 1) + 0.39 - 0.61 / er));
    }

    const W = clamp(u, 0.001, 1000) * h;
    const chk = msAnalysis(W, h, er, t || 0, null, 0);
    return { W, eeff: chk ? chk.eeff : er, Z0_check: chk ? chk.Z0 : null };
  }

  // ── Electrical & physical length ──────────────────────────────────────
  function electricalLength(L_mm, freq_GHz, eeff) {
    if (!freq_GHz || freq_GHz <= 0 || !eeff || eeff <= 0) return null;
    return (L_mm * freq_GHz * Math.sqrt(eeff) / C0) * 360; // °
  }

  function physicalLength(theta_deg, freq_GHz, eeff) {
    if (!freq_GHz || freq_GHz <= 0 || !eeff || eeff <= 0) return null;
    return (theta_deg / 360) * (C0 / (freq_GHz * Math.sqrt(eeff))); // mm
  }

  // ── Coupled microstrip analysis (simplified Pozar) ────────────────────
  // Returns { Z0e, Z0o, C_dB, eeff_e, eeff_o }
  function coupleAnalysis(W, gap, h, er, t, freq_GHz, tanD) {
    if (W <= 0 || gap <= 0 || h <= 0 || er < 1) return null;
    // Compute single-line eeff and Z0 for reference
    const ms = msAnalysis(W, h, er, t, freq_GHz, tanD);
    if (!ms) return null;

    // Even-mode: gap adds to effective dielectric fill (image charges move closer)
    // Odd-mode: gap reduces coupling
    // Simplified: Mohan et al. (1977) approximation
    const Q = gap / h;
    const ae = 1 - Math.exp(-0.693 * Math.pow(Q + 0.5, 1.2));
    const ao = Math.exp(-0.693 * Math.pow(Q, 0.84));

    const Z0e = ms.Z0 * (1 + ae * 0.45);
    const Z0o = ms.Z0 * (1 - ao * 0.38);
    const C_dB = 20 * Math.log10(Math.abs((Z0e - Z0o) / (Z0e + Z0o)));

    return {
      Z0e,
      Z0o,
      C_dB,
      Z0_port : Math.sqrt(Z0e * Z0o),       // port impedance for matched coupler
      eeff_e  : ms.eeff * (1 + 0.05 * ae),
      eeff_o  : ms.eeff * (1 - 0.04 * ao),
      lambda_g: ms.lambda_g
    };
  }

  // ── Via inductance (IPC-2141 / Wadell 1991) ───────────────────────────
  // h = board thickness (mm), drill = drill diameter (mm)
  // Returns inductance in pH
  function viaInductance(h, drill) {
    if (h <= 0 || drill <= 0) return null;
    const d = clamp(drill, 0.05, h);
    // L = μ₀/(2π) * h * [ln(4h/d) + 1 - sqrt(1+(2h/d)²) + sqrt(1+(d/(2h))²) + d/(2h)]  pH
    const rat = 2 * h / d;
    const L_nH = (2e-4 * h) * (Math.log(rat) + 0.5 * Math.log(1 + rat * rat) - 0.5 + 1 / rat);
    return L_nH * 1000; // pH
  }

  // ── Open stub input impedance ─────────────────────────────────────────
  // Returns Zin (complex as {re, im}) for open-circuited shunt stub
  function openStubZin(Z0, theta_deg) {
    const theta = theta_deg * Math.PI / 180;
    // Zin = -j·Z0·cot(θ)
    const cot = Math.cos(theta) / (Math.sin(theta) || 1e-9);
    return { re: 0, im: -Z0 * cot };
  }

  // ── Short stub input impedance ────────────────────────────────────────
  function shortStubZin(Z0, theta_deg) {
    const theta = theta_deg * Math.PI / 180;
    // Zin = j·Z0·tan(θ)
    const tan = Math.tan(theta);
    return { re: 0, im: Z0 * tan };
  }

  // ── Quarter-wave frequency ────────────────────────────────────────────
  function quarterWaveFreq(L_mm, eeff) {
    if (L_mm <= 0 || eeff <= 0) return null;
    return C0 / (4 * L_mm * Math.sqrt(eeff)); // GHz
  }

  // ── HTML rendering helpers ────────────────────────────────────────────
  function fmtZ(v) {
    if (v == null || isNaN(v)) return '\u2014';
    return v.toFixed(1) + '\u00a0\u03a9';
  }
  function fmtDeg(v) {
    if (v == null || isNaN(v)) return '\u2014';
    return v.toFixed(1) + '\u00b0';
  }
  function fmtMm(v) {
    if (v == null || isNaN(v)) return '\u2014';
    return v.toFixed(3) + '\u00a0mm';
  }
  function fmtN(v, dp) {
    if (v == null || isNaN(v)) return '\u2014';
    return v.toFixed(dp != null ? dp : 3);
  }
  function fmtdB(v) {
    if (v == null || isNaN(v)) return '\u2014';
    return v.toFixed(1) + '\u00a0dB';
  }

  function row(label, value, cls) {
    return '<div class="rfcad-rf-row">' +
      '<span class="rfcad-rf-label">' + label + '</span>' +
      '<span class="rfcad-rf-value' + (cls ? ' ' + cls : '') + '">' + value + '</span>' +
      '</div>';
  }

  function section(title, content) {
    return '<div class="rfcad-rf-section">' +
      '<div class="rfcad-rf-section-title">' + title + '</div>' +
      content +
      '</div>';
  }

  // ── Main display update ───────────────────────────────────────────────
  // Call this after component selection or substrate/freq change.
  // containerId: DOM id of the display div
  // comp: component object {type, params:{W,L,gap,drill,pad,portNum}}
  // substrate: {er, tanD, h, t}
  // freqGHz: number
  function updateDisplay(containerId, comp, substrate, freqGHz) {
    const el = document.getElementById(containerId);
    if (!el) return;
    if (!comp) { el.innerHTML = '<div class="rfcad-rf-placeholder">Select a component to see RF parameters.</div>'; return; }

    const sub  = substrate || {};
    const p    = comp.params || {};
    const er   = sub.er   || 4.4;
    const tanD = sub.tanD || sub.tand || 0.002;   // accept both cases
    const h    = sub.h    || 0.5;
    const t    = sub.t    || 0.035;
    const f    = freqGHz  || null;
    const type = comp.type || 'ms';

    let html = '';

    if (type === 'ms' || type === 'bend90' || type === 'open_stub' || type === 'short_stub' || type === 'tee') {
      const W = p.W || 0.5;
      const L = p.L || 5.0;
      const r = msAnalysis(W, h, er, t, f, tanD);
      if (r) {
        let rows = '';
        rows += row('Z\u2080', fmtZ(r.Z0), r.Z0 > 80 ? 'rfcad-warn' : r.Z0 < 20 ? 'rfcad-warn' : '');
        rows += row('\u03b5<sub>eff</sub>', fmtN(r.eeff, 3));
        rows += row('W<sub>eff</sub>', fmtMm(r.Weff));
        if (f) {
          const theta = electricalLength(L, f, r.eeff);
          rows += row('\u03b8(L)', fmtDeg(theta), Math.abs(theta - 90) < 5 ? 'rfcad-accent' : '');
          rows += row('\u03bb<sub>g</sub>', fmtMm(r.lambda_g));
          if (r.alpha_c != null) rows += row('\u03b1<sub>c</sub>', fmtN(r.alpha_c * 1000, 2) + '\u00a0mdB/mm');
          if (r.alpha_d != null) rows += row('\u03b1<sub>d</sub>', fmtN(r.alpha_d * 1000, 2) + '\u00a0mdB/mm');
          const f_qw = quarterWaveFreq(L, r.eeff);
          if (f_qw) rows += row('f\u00bc\u03bb', fmtN(f_qw, 3) + '\u00a0GHz');
        }
        html += section('Microstrip Analysis', rows);

        if (type === 'open_stub' || type === 'short_stub') {
          if (f) {
            const theta = electricalLength(L, f, r.eeff);
            const zin = type === 'open_stub' ? openStubZin(r.Z0, theta) : shortStubZin(r.Z0, theta);
            let srows = '';
            srows += row('Z<sub>in</sub>', fmtN(zin.im, 1) + '\u00a0\u03a9 (j)');
            const Bin = -zin.im / (r.Z0 * r.Z0 + zin.im * zin.im);
            srows += row('B<sub>in</sub>', fmtN(Bin * 1000, 2) + '\u00a0mS');
            html += section('Stub Input Impedance', srows);
          }
        }
      }
    }

    if (type === 'coupled') {
      const W   = p.W   || 0.5;
      const L   = p.L   || 5.0;
      const gap = p.gap || 0.2;
      const r = coupleAnalysis(W, gap, h, er, t, f, tanD);
      if (r) {
        let rows = '';
        rows += row('Z<sub>0e</sub>', fmtZ(r.Z0e));
        rows += row('Z<sub>0o</sub>', fmtZ(r.Z0o));
        rows += row('Z<sub>port</sub>', fmtZ(r.Z0_port));
        rows += row('C', fmtdB(r.C_dB), 'rfcad-accent');
        if (f && r.lambda_g) {
          const ms_base = msAnalysis(W, h, er, t, f, tanD);
          if (ms_base) {
            const theta = electricalLength(L, f, ms_base.eeff);
            rows += row('\u03b8(L)', fmtDeg(theta));
            rows += row('\u03bb<sub>g</sub>', fmtMm(r.lambda_g));
          }
        }
        html += section('Coupled-Line Analysis', rows);
      }
    }

    if (type === 'via') {
      const drill = p.drill || 0.3;
      const pad   = p.pad   || 0.6;
      const L_vh  = viaInductance(h, drill);
      let rows = '';
      rows += row('Inductance', L_vh ? fmtN(L_vh, 1) + '\u00a0pH' : '\u2014');
      rows += row('Drill', fmtMm(drill));
      rows += row('Pad \u00d8', fmtMm(pad));
      rows += row('Annular ring', fmtMm((pad - drill) / 2));
      if (f && L_vh) {
        const Xl_ohm = 2 * Math.PI * f * 1e9 * L_vh * 1e-12;
        rows += row('X<sub>L</sub> @ f', fmtN(Xl_ohm, 2) + '\u00a0\u03a9');
      }
      html += section('Via Analysis', rows);
    }

    if (type === 'port') {
      html += '<div class="rfcad-rf-placeholder">RF port P' + (p.portNum || 1) + '. Excitation defined in OpenEMS (Phase 5).</div>';
    }

    if (!html) {
      html = '<div class="rfcad-rf-placeholder">No RF analysis available for this component type.</div>';
    }

    el.innerHTML = html;
  }

  // ── Export ────────────────────────────────────────────────────────────
  global.rfCalc = {
    msAnalysis,
    msSynthesis,
    coupleAnalysis,
    viaInductance,
    electricalLength,
    physicalLength,
    quarterWaveFreq,
    openStubZin,
    shortStubZin,
    updateDisplay,
    // convenient wrappers
    lambdaG : (freq_GHz, eeff) => eeff > 0 && freq_GHz > 0
      ? C0 / (freq_GHz * Math.sqrt(eeff)) : null
  };

})(window);
