/*!
 * RF 3D Viewer — Phase 3
 * Three.js-based 3D stackup viewer for RF CAD designs.
 *
 * Usage:
 *   RF3D.render(designJSON, containerId)  — render (or re-render) in container
 *   RF3D.clear(containerId)               — dispose scene
 *
 * designJSON format: { substrate:{h,er,t}, components:[{type,x,y,rotation,layer,params},...] }
 * All units: mm → converted to Three.js units (1 unit = 1 mm)
 */
(function (global) {
  'use strict';

  // ── Layer Z-positions and colours ──────────────────────────────────────────
  const LAYER_Z = {
    metal_top     : 1,    // top of substrate
    metal_bot     : 0,    // bottom of substrate (negative offset applied later)
    metal_inner_1 : 0.5,
    metal_inner_2 : 0.33
  };

  const LAYER_COLOR = {
    metal_top     : 0xc8a84b,
    metal_bot     : 0x7b9fc7,
    metal_inner_1 : 0x8fcf70,
    metal_inner_2 : 0xc878c8,
    via           : 0xd4d4d4,
    port          : 0xff6b6b
  };

  const SUB_COLOR   = 0x2a4a2a;   // dark green for substrate dielectric
  const BORDER_CLR  = 0x444466;   // outline edge color

  // Active scene registry (by containerId)
  const scenes = {};

  // ── Build one Three.js scene from design JSON ───────────────────────────
  function buildScene(renderer, design) {
    const THREE  = global.THREE;
    const scene  = new THREE.Scene();
    scene.background = new THREE.Color(0x0f0f1a);

    const sub   = design.substrate || {};
    const h     = sub.h || 0.508;   // substrate height mm
    const t     = sub.t || 0.035;   // copper thickness mm
    const comps = design.components || [];

    // ── Bounding box of all components ─────────────────────────────────
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    comps.forEach(c => {
      const p  = c.params || {};
      const W  = p.W || 0.5;
      const L  = p.L || 2.0;
      minX = Math.min(minX, c.x - W / 2);
      minY = Math.min(minY, c.y - W / 2);
      maxX = Math.max(maxX, c.x + L + W / 2);
      maxY = Math.max(maxY, c.y + W / 2);
    });
    const padX = Math.max(2, (maxX - minX) * 0.12);
    const padY = Math.max(2, (maxY - minY) * 0.12);
    if (!isFinite(minX)) { minX = 0; minY = 0; maxX = 10; maxY = 10; }

    const boardW = maxX - minX + 2 * padX;
    const boardL = maxY - minY + 2 * padY;
    const cx     = (minX + maxX) / 2;
    const cy     = (minY + maxY) / 2;

    // ── Substrate slab ─────────────────────────────────────────────────
    const subGeo = new THREE.BoxGeometry(boardW, h, boardL);
    const subMat = new THREE.MeshPhongMaterial({
      color       : SUB_COLOR,
      transparent : true,
      opacity     : 0.85,
      shininess   : 20
    });
    const subMesh = new THREE.Mesh(subGeo, subMat);
    subMesh.position.set(0, h / 2, 0);
    scene.add(subMesh);

    // Substrate outline
    const subEdge = new THREE.LineSegments(
      new THREE.EdgesGeometry(subGeo),
      new THREE.LineBasicMaterial({ color: BORDER_CLR })
    );
    subEdge.position.copy(subMesh.position);
    scene.add(subEdge);

    // εr label (substrate info text via HTML overlay — handled in R)

    // ── Component meshes ────────────────────────────────────────────────
    comps.forEach(comp => {
      const p       = comp.params  || {};
      const type    = comp.type    || 'ms';
      const layer   = comp.layer   || 'metal_top';
      const color   = LAYER_COLOR[layer] || LAYER_COLOR.metal_top;
      const rotDeg  = comp.rotation || 0;
      const rotRad  = rotDeg * Math.PI / 180;
      const W       = p.W     || 0.5;
      const L       = p.L     || 2.0;
      const lx      = (comp.x || 0) - cx;
      const lz      = (comp.y || 0) - cy;

      // Y elevation: top of substrate + half copper thickness
      const baseY = layer === 'metal_bot'
        ? -(t / 2)                      // below substrate
        : h + (LAYER_Z[layer] || 1) * 0 + t / 2;  // above substrate top

      const mat3d = new THREE.MeshPhongMaterial({ color, shininess: 80 });

      if (type === 'ms' || type === 'open_stub' || type === 'short_stub') {
        // Straight line: box W × t × L centred at (lx+L/2, baseY, lz)
        const geo = new THREE.BoxGeometry(L, t, W);
        const m   = new THREE.Mesh(geo, mat3d);
        m.position.set(lx + L / 2, baseY, lz);
        m.rotation.y = -rotRad;
        scene.add(m);

      } else if (type === 'bend90') {
        // Approximate as two half-length arms forming an L
        const armL = L / 2;
        const geo1 = new THREE.BoxGeometry(armL, t, W);
        const m1   = new THREE.Mesh(geo1, mat3d.clone());
        m1.position.set(lx + armL / 2, baseY, lz);
        scene.add(m1);

        const geo2 = new THREE.BoxGeometry(W, t, armL);
        const m2   = new THREE.Mesh(geo2, mat3d.clone());
        m2.position.set(lx + armL, baseY, lz + armL / 2);
        scene.add(m2);

      } else if (type === 'tee') {
        // Main line + perpendicular stub
        const geo1 = new THREE.BoxGeometry(L, t, W);
        const m1   = new THREE.Mesh(geo1, mat3d.clone());
        m1.position.set(lx + L / 2, baseY, lz);
        scene.add(m1);

        const sL = L * 0.4;
        const geo2 = new THREE.BoxGeometry(W, t, sL);
        const m2   = new THREE.Mesh(geo2, mat3d.clone());
        m2.position.set(lx + L / 2, baseY, lz + sL / 2 + W / 2);
        scene.add(m2);

      } else if (type === 'coupled') {
        const gap = p.gap || 0.2;
        const geo1 = new THREE.BoxGeometry(L, t, W);
        const m1   = new THREE.Mesh(geo1, mat3d.clone());
        m1.position.set(lx + L / 2, baseY, lz - (W + gap) / 2);
        scene.add(m1);

        const m2 = new THREE.Mesh(geo1.clone(), mat3d.clone());
        m2.position.set(lx + L / 2, baseY, lz + (W + gap) / 2);
        scene.add(m2);

      } else if (type === 'via') {
        const drill  = (p.drill || 0.3) / 2;
        const pad    = (p.pad   || 0.6) / 2;
        const vGeo   = new THREE.CylinderGeometry(drill, drill, h + 2 * t, 16);
        const vMesh  = new THREE.Mesh(vGeo,
          new THREE.MeshPhongMaterial({ color: LAYER_COLOR.via, shininess: 100 }));
        vMesh.position.set(lx, h / 2, lz);
        scene.add(vMesh);

        // Top pad ring
        const padTop = new THREE.Mesh(
          new THREE.CylinderGeometry(pad, pad, t * 0.5, 24),
          new THREE.MeshPhongMaterial({ color: LAYER_COLOR.metal_top, shininess: 80 })
        );
        padTop.position.set(lx, h + t / 2, lz);
        scene.add(padTop);

      } else if (type === 'port') {
        const portW = W || 0.5;
        const geo = new THREE.BoxGeometry(0.4, t * 2, portW);
        const m   = new THREE.Mesh(geo,
          new THREE.MeshPhongMaterial({ color: LAYER_COLOR.port, shininess: 60 }));
        m.position.set(lx, baseY, lz);
        scene.add(m);

        // Port number label (sphere marker)
        const numSphere = new THREE.Mesh(
          new THREE.SphereGeometry(0.25, 8, 8),
          new THREE.MeshPhongMaterial({ color: LAYER_COLOR.port })
        );
        numSphere.position.set(lx, baseY + 0.5, lz);
        scene.add(numSphere);
      }
    });

    // ── Lighting ────────────────────────────────────────────────────────
    scene.add(new THREE.AmbientLight(0x404060, 0.8));

    const dirLight = new THREE.DirectionalLight(0xffffff, 0.9);
    dirLight.position.set(boardW * 0.6, boardW * 1.2, boardL * 0.6);
    scene.add(dirLight);

    const fillLight = new THREE.DirectionalLight(0x8899bb, 0.4);
    fillLight.position.set(-boardW, h * 2, -boardL);
    scene.add(fillLight);

    // Returns scene and recommended camera distance
    return { scene, cx, cy, h, boardW, boardL };
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  function render(designJSON, containerId) {
    const THREE = global.THREE;
    if (!THREE) { console.error('[RF3D] Three.js not loaded'); return; }

    const container = document.getElementById(containerId);
    if (!container) return;

    // Dispose previous scene for this container
    clear(containerId);

    // Parse design
    let design;
    try { design = typeof designJSON === 'string' ? JSON.parse(designJSON) : designJSON; }
    catch (e) { console.error('[RF3D] JSON parse error', e); return; }

    const W = container.offsetWidth  || 600;
    const H = container.offsetHeight || 400;

    // Renderer
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(W, H);
    renderer.setPixelRatio(window.devicePixelRatio || 1);
    container.appendChild(renderer.domElement);

    // Scene
    const { scene, cx, cy, h, boardW, boardL } = buildScene(renderer, design);

    // Camera
    const camDist = Math.max(boardW, boardL) * 1.8;
    const camera  = new THREE.PerspectiveCamera(45, W / H, 0.01, camDist * 10);
    camera.position.set(boardW * 0.7, camDist * 0.55, boardL * 0.9);
    camera.lookAt(0, h / 2, 0);

    // OrbitControls (if available)
    let controls = null;
    if (THREE.OrbitControls) {
      controls = new THREE.OrbitControls(camera, renderer.domElement);
      controls.target.set(0, h / 2, 0);
      controls.enableDamping = true;
      controls.dampingFactor = 0.08;
      controls.update();
    }

    // Animation loop
    let animId;
    function animate() {
      animId = requestAnimationFrame(animate);
      if (controls) controls.update();
      renderer.render(scene, camera);
    }
    animate();

    // Resize observer
    if (window.ResizeObserver) {
      const ro = new ResizeObserver(() => {
        const nW = container.offsetWidth;
        const nH = container.offsetHeight;
        camera.aspect = nW / nH;
        camera.updateProjectionMatrix();
        renderer.setSize(nW, nH);
      });
      ro.observe(container);
      scenes[containerId] = { renderer, scene, camera, controls, animId, ro };
    } else {
      scenes[containerId] = { renderer, scene, camera, controls, animId };
    }
  }

  function clear(containerId) {
    const s = scenes[containerId];
    if (!s) return;
    cancelAnimationFrame(s.animId);
    if (s.controls) s.controls.dispose();
    if (s.ro)       s.ro.disconnect();
    s.renderer.dispose();
    const el = document.getElementById(containerId);
    if (el) el.innerHTML = '';
    delete scenes[containerId];
  }

  global.RF3D = { render, clear };

})(typeof window !== 'undefined' ? window : this);
