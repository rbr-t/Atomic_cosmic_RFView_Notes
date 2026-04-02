# JavaScript Updates Required - Power Calculation Fixes

## Issues to Address:

### 3. Power Calculations (Back-calculate from P3dB)
**Problem**: Current calculations don't properly use P3dB as reference output power
**Solution**: Modify component generation to work backwards from P3dB

### 6. Combiner Power Calculation
**Problem**: Combined power from main + aux is less than expected
**Solution**: Fix power combining formula (should be 10*log10(P_main_watts + P_aux_watts) + 30)

### 7. P1dB vs Pout Display Clarification
**Problem**: P1dB > Pout shown, which is incorrect. Need Pin, Pout(P3dB), P1dB distinction
**Solution**: Update component property labels and displays

---

## Required JavaScript Code Changes

### Change 1: Fix Transistor Component Display Labels
**File**: www/js/pa_lineup_canvas.js
**Location**: Around line 1025-1050

```javascript
// CURRENT CODE (lines ~1025-1050):
if (display.includes('pout')) {
  const poutValue = component.properties.pout || 40;
  const poutText = this.formatPower(poutValue, this.powerUnit);
  textGroup.append('text')
    .attr('x', 15)
    .attr('y', yOffset)
    .attr('text-anchor', 'middle')
    .attr('fill', '#ff88ff')
    .attr('font-size', '8px')
    .text(`Pout: ${poutText}`);
  yOffset += 10;
}

if (display.includes('p1db')) {
  const p1dbValue = component.properties.p1db || component.properties.pout || 40;
  const p1dbText = this.formatPower(p1dbValue, this.powerUnit);
  textGroup.append('text')
    .attr('x', 15)
    .attr('y', yOffset)
    .attr('text-anchor', 'middle')
    .attr('fill', '#ffaa00')
    .attr('font-size', '8px')
    .text(`P1dB: ${p1dbText}`);
  yOffset += 10;
}

// SHOULD BE CHANGED TO:
// Add Pin display
if (display.includes('pin')) {
  const pinValue = component.properties.pin || 30;
  const pinText = this.formatPower(pinValue, this.powerUnit);
  textGroup.append('text')
    .attr('x', 15)
    .attr('y', yOffset)
    .attr('text-anchor', 'middle')
    .attr('fill', '#88ccff')
    .attr('font-size', '8px')
    .text(`Pin: ${pinText}`);
  yOffset += 10;
}

// Clarify Pout as P3dB
if (display.includes('pout') || display.includes('p3db')) {
  const p3dbValue = component.properties.p3db || component.properties.pout || 40;
  const p3dbText = this.formatPower(p3dbValue, this.powerUnit);
  textGroup.append('text')
    .attr('x', 15)
    .attr('y', yOffset)
    .attr('text-anchor', 'middle')
    .attr('fill', '#ff88ff')
    .attr('font-size', '8px')
    .text(`Pout(P3dB): ${p3dbText}`);
  yOffset += 10;
}

// P1dB must be below P3dB
if (display.includes('p1db')) {
  const p3dbValue = component.properties.p3db || component.properties.pout || 40;
  const p1dbValue = component.properties.p1db || (p3dbValue - 2);  // 2dB below P3dB typical
  const p1dbText = this.formatPower(p1dbValue, this.powerUnit);
  textGroup.append('text')
    .attr('x', 15)
    .attr('y', yOffset)
    .attr('text-anchor', 'middle')
    .attr('fill', '#ffaa00')
    .attr('font-size', '8px')
    .text(`P1dB: ${p1dbText}`);
  yOffset += 10;
}

// Add Pavg (backoff power) display
if (display.includes('pavg')) {
  const p3dbValue = component.properties.p3db || component.properties.pout || 40;
  const backoff = component.properties.backoff || 6;
  const pavgValue = p3dbValue - backoff;
  const pavgText = this.formatPower(pavgValue, this.powerUnit);
  textGroup.append('text')
    .attr('x', 15)
    .attr('y', yOffset)
    .attr('text-anchor', 'middle')
    .attr('fill', '#ffff88')
    .attr('font-size', '8px')
    .text(`Pavg(BO): ${pavgText}`);
  yOffset += 10;
}
```

---

### Change 2: Fix Power Calculation - Back-calculate from P3dB
**Explanation**: The lineup output (P3dB) should be the starting point, then work backward to calculate required power at each stage.

**New function to add** (around line 7500):

```javascript
/**
 * Back-calculate power levels from final P3dB output
 * @param {number} p3db_output - Target output power (dBm)
 * @param {array} stages - Array of stage objects with gain values
 * @param {object} losses - Passive component losses
 * @returns {object} Power levels for each stage
 */
function backCalculatePowerLevels(p3db_output, stages, losses) {
  console.log('=== Back-Calculating Power Levels ===');
  console.log(`Target Output (P3dB): ${p3db_output.toFixed(2)} dBm`);
  
  const powerLevels = [];
  let currentPower = p3db_output;
  
  // Work backwards through stages
  for (let i = stages.length - 1; i >= 0; i--) {
    const stage = stages[i];
    
    // Output of this stage
    const pout = currentPower;
    
    // Input to this stage (subtract gain)
    const pin = pout - stage.gain;
    
    // P3dB of this stage (should match or exceed output)
    const p3db = pout;
    
    // P1dB typically 2dB below P3dB for solid state
    const p1db = p3db - 2;
    
    powerLevels.unshift({
      stage_name: stage.name,
      pin: pin,
      pout: pout,
      p3db: p3db,
      p1db: p1db,
      gain: stage.gain
    });
    
    console.log(`  ${stage.name}: Pin=${pin.toFixed(1)} → Pout=${pout.toFixed(1)} dBm (Gain=${stage.gain.toFixed(1)}dB)`);
    
    // Move to previous stage (account for any losses between stages)
    if (i > 0 && losses && losses[i-1]) {
      currentPower = pin - losses[i-1];
      console.log(`    Loss between stages: ${losses[i-1].toFixed(2)} dB → ${currentPower.toFixed(1)} dBm`);
    } else {
      currentPower = pin;
    }
  }
  
  console.log(`Lineup Input Required: ${currentPower.toFixed(2)} dBm`);
  console.log('=== Power Calculation Complete ===\n');
  
  return {
    levels: powerLevels,
    lineup_pin: currentPower,
    lineup_pout: p3db_output
  };
}
```

---

### Change 3: Fix Doherty Combiner Power Calculation
**Problem**: Currently not properly combining main + aux PA powers

**New function to add** (around line 7600):

```javascript
/**
 * Calculate combined power from Doherty main and auxiliary PAs
 * @param {number} main_p3db - Main PA P3dB (dBm)
 * @param {number} aux_p3db - Aux PA P3dB (dBm)  
 * @param {number} combiner_loss - Combiner insertion loss (dB)
 * @returns {number} Combined output power (dBm)
 */
function calculateDohertyCombinedPower(main_p3db, aux_p3db, combiner_loss) {
  // Convert dBm to watts
  const main_watts = Math.pow(10, (main_p3db - 30) / 10);
  const aux_watts = Math.pow(10, (aux_p3db - 30) / 10);
  
  // Combine powers (add in watts domain)
  const combined_watts = main_watts + aux_watts;
  
  // Convert back to dBm
  const combined_dbm = 10 * Math.log10(combined_watts) + 30;
  
  // Subtract combiner loss
  const final_power = combined_dbm - combiner_loss;
  
  console.log(`Doherty Combiner:`);
  console.log(`  Main PA: ${main_p3db.toFixed(2)} dBm (${main_watts.toFixed(1)} W)`);
  console.log(`  Aux PA: ${aux_p3db.toFixed(2)} dBm (${aux_watts.toFixed(1)} W)`);
  console.log(`  Combined: ${combined_dbm.toFixed(2)} dBm (${combined_watts.toFixed(1)} W)`);
  console.log(`  After combiner loss (${combiner_loss.toFixed(2)} dB): ${final_power.toFixed(2)} dBm`);
  
  return final_power;
}
```

---

### Change 4: Update Single Doherty Template Generation
**Location**: Search for where Single Doherty template is created (likely around line 2300-2700)

**Modified template generation** (this is conceptual - find the actual function and modify):

```javascript
// EXAMPLE - find actual function and modify
function generateSingleConventionalDoherty(specs) {
  console.log('=== Generating Single Conventional Doherty from Specs ===');
  
  // Get target specs
  const freq_ghz = specs.frequency;
  const p3db_target = specs.p3db;  // THIS IS OUTPUT POWER
  const gain_total = specs.gain;
  const vdd = specs.supply_voltage;
  
  // Technology selection
  const technology = selectTechnology(freq_ghz, p3db_target, vdd);
  
  // Estimate losses
  const splitter_loss = estimatePassiveLoss('wilkinson_splitter', freq_ghz, {});
  const combiner_loss = estimatePassiveLoss('doherty_combiner', freq_ghz, {});
  const tx_line_loss = estimatePassiveLoss('transmission_line', freq_ghz, {length: 5});  // 5cm typical
  
  console.log(`Losses: Splitter=${splitter_loss.toFixed(2)}dB, Combiner=${combiner_loss.toFixed(2)}dB, TxLine=${tx_line_loss.toFixed(2)}dB`);
  
  // Determine stage gains
  const gains = distributeGain(gain_total, 3);  // 3 stages: Driver, Main, Aux
  const driver_gain = gains[0];
  const pa_gain = gains[1];  // Same for main and aux
  
  // CRITICAL: Back-calculate from OUTPUT
  // For Doherty, main and aux combine at EQUAL power
  // So each PA needs to produce: P3dB_target - 3dB (power split) - combiner_loss
  const pa_pout_required = p3db_target - 3.01 - combiner_loss;  // 3.01 dB = 10*log10(2) for 2-way combining
  
  // Main PA parameters
  const main_pa = {
    label: 'Main PA',
    freq: freq_ghz,
    technology: technology,
    biasClass: 'AB',
    
    // Power levels (KEY FIX)
    p3db: pa_pout_required,          // P3dB capability
    pout: pa_pout_required,          // Actual output at P3dB
    p1db: pa_pout_required - 2,      // P1dB below P3dB
    pin: pa_pout_required - pa_gain, // Input power needed
    
    gain: pa_gain,
    vdd: vdd,
    pae: estimatePAE(technology, 'AB', freq_ghz),
    
    // Display flags
    display: ['pin', 'p3db', 'p1db', 'gain', 'pae']
  };
  
  // Aux PA parameters (matched toTo main)
  const aux_pa = {
    label: 'Aux PA',
    freq: freq_ghz,
    technology: technology,
    biasClass: 'C',
    
     // Power levels (same as main for balanced Doherty)
    p3db: pa_pout_required,
    pout: pa_pout_required,
    p1db: pa_pout_required - 2,
    pin: pa_pout_required - pa_gain,
    
    gain: pa_gain,
    vdd: vdd,
    pae: estimatePAE(technology, 'C', freq_ghz),
    
    display: ['pin', 'p3db', 'p1db', 'gain', 'pae']
  };
  
  // Driver stage (needs to provide power to splitter)
  // Splitter input needed: PA input + splitter_loss + 3dB (split to 2 outputs)
  const driver_pout_required = main_pa.pin + splitter_loss + 3.01;
  
  const driver = {
    label: 'Driver',
    freq: freq_ghz,
    technology: technology,
    biasClass: 'A',  // Linear for clean signal
    
    p3db: driver_pout_required,
    pout: driver_pout_required,
    p1db: driver_pout_required - 2,
    pin: driver_pout_required - driver_gain,
    
    gain: driver_gain,
    vdd: vdd,
    pae: estimatePAE(technology, 'A', freq_ghz),
    
    display: ['pin', 'p3db', 'p1db', 'gain', 'pae']
  };
  
  // Lineup input power
  const lineup_pin = driver.pin;
  
  // Verify total gain
  const calculated_gain = driver_pout_required - lineup_pin + pa_gain;
  console.log(`Total Gain Check: Target=${gain_total}dB, Calculated=${calculated_gain.toFixed(1)}dB`);
  
  // Calculate combined output
  const combined_power = calculateDohertyCombinedPower(main_pa.p3db, aux_pa.p3db, combiner_loss);
  console.log(`Final Lineup Output: ${combined_power.toFixed(2)} dBm (Target: ${p3db_target} dBm)`);
  
  return {
    driver: driver,
    main_pa: main_pa,
    aux_pa: aux_pa,
    splitter: {
      loss: splitter_loss,
      type: 'wilkinson'
    },
    combiner: {
      loss: combiner_loss,
      type: 'doherty',
      combined_power: combined_power
    },
    lineup_summary: {
      pin: lineup_pin,
      pout: combined_power,
      gain_calculated: combined_power - lineup_pin,
      gain_target: gain_total
    }
  };
}
```

---

### Change 5: Update Component Default Display Properties
**Location**: Where default transistor properties are set (search for "display:" in component definitions)

**Change default display** from:
```javascript
display: ['pout', 'gain', 'pae']
```

**To**:
```javascript
display: ['pin', 'p3db', 'p1db', 'gain', 'pae']  // Show Pin, P3dB (Pout), P1dB, Gain, PAE
```

---

## Testing After Changes:

1. **Load Single Doherty template** with specs: 1805 MHz, 55.3 dBm, 41.5 dB gain
2. **Check Driver**: 
   - Pin should be ~13-15 dBm
   - P3dB (Pout) should be ~28-30 dBm
   - P1dB should be ~26-28 dBm (2dB below P3dB)
   
3. **Check Main PA**:
   - Pin should be ~42-44 dBm  
   - P3dB should be ~55-56 dBm
   - P1dB should be ~53-54 dBm (2dB below P3dB)
   - **P1dB must always be < P3dB!**
   
4. **Check Aux PA**: Same as Main for balanced Doherty

5. **Check Combined Output**: Should be ~55.3 dBm (matching spec)

6. **Verify**: P1dB < Pout(P3dB) for ALL stages

---

## Priority Order:

1. **Highest**: Fix P1dB display (must be < P3dB)  
2. **High**: Back-calculate power from P3dB output
3. **High**: Fix combiner power calculation
4. **Medium**: Clarify Pin/Pout/P1dB labels in display
5. **Medium**: Add Pavg (backoff) display option

---

*Ready to implement these changes?*
