#!/usr/bin/env python3
"""
PA Figure Generation Scripts (Python)
Advanced plotting functions for power amplifier analysis
Author: PA Design Reference Manual
Date: February 1, 2026
"""

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import Circle
from scipy.interpolate import griddata
import seaborn as sns

# Set style
plt.style.use('seaborn-v0_8-darkgrid')
sns.set_palette("husl")

# ============================================================================
# SMITH CHART PLOTTING
# ============================================================================

def plot_smith_chart(gamma_complex=None, labels=None, title="Smith Chart", 
                     show_grid=True, impedances=None):
    """
    Plot Smith chart with optional impedance points
    
    Args:
        gamma_complex: Complex reflection coefficients (array)
        labels: Labels for each point (list of strings)
        title: Plot title
        show_grid: Show constant R and X circles
        impedances: Complex impedances to plot (will be converted to gamma)
    
    Returns:
        fig, ax: Matplotlib figure and axis objects
    """
    fig, ax = plt.subplots(figsize=(10, 10))
    
    # Outer circle (|Γ| = 1)
    outer_circle = Circle((0, 0), 1, fill=False, edgecolor='black', linewidth=2)
    ax.add_patch(outer_circle)
    
    if show_grid:
        # Constant resistance circles
        r_values = [0.2, 0.5, 1.0, 2.0, 5.0]
        for r in r_values:
            center_x = r / (1 + r)
            radius = 1 / (1 + r)
            circle = Circle((center_x, 0), radius, fill=False, 
                          edgecolor='gray', linewidth=0.5, linestyle='--')
            ax.add_patch(circle)
            # Label
            ax.text(center_x + radius, 0.05, f'{r}Ω', fontsize=8, color='gray')
        
        # Constant reactance circles (upper half only, symmetry)
        x_values = [0.2, 0.5, 1.0, 2.0, 5.0]
        for x in x_values:
            # Center and radius for reactance circles
            center_y = 1.0 / x
            radius = 1.0 / x
            
            # Draw upper arc
            theta = np.linspace(-np.pi/2, np.pi/2, 100)
            circle_x = 1 + radius * np.cos(theta)
            circle_y = center_y + radius * np.sin(theta)
            ax.plot(circle_x, circle_y, 'gray', linewidth=0.5, linestyle='--')
            
            # Draw lower arc
            circle_y_lower = -center_y + radius * np.sin(theta)
            ax.plot(circle_x, circle_y_lower, 'gray', linewidth=0.5, linestyle='--')
            
            # Label (upper)
            ax.text(0.98, center_y - 0.05, f'+j{x}', fontsize=8, color='gray', ha='right')
            # Label (lower)
            ax.text(0.98, -center_y + 0.05, f'-j{x}', fontsize=8, color='gray', ha='right')
    
    # Center point (50 Ohm)
    ax.plot(0, 0, 'r+', markersize=15, markeredgewidth=2)
    ax.text(0.05, 0.05, '50Ω', fontsize=10, color='red', fontweight='bold')
    
    # Plot impedance points
    if impedances is not None:
        # Convert impedances to reflection coefficients
        z0 = 50  # Reference impedance
        gamma_complex = (impedances - z0) / (impedances + z0)
    
    if gamma_complex is not None:
        gamma_real = np.real(gamma_complex)
        gamma_imag = np.imag(gamma_complex)
        
        # Plot points
        ax.scatter(gamma_real, gamma_imag, s=100, c='blue', 
                  marker='o', edgecolors='black', linewidth=1.5, zorder=10)
        
        # Add labels if provided
        if labels is not None:
            for i, (gr, gi, label) in enumerate(zip(gamma_real, gamma_imag, labels)):
                ax.annotate(label, (gr, gi), xytext=(10, 10), 
                           textcoords='offset points', fontsize=9,
                           bbox=dict(boxstyle='round,pad=0.3', facecolor='yellow', alpha=0.7))
    
    ax.set_xlim(-1.1, 1.1)
    ax.set_ylim(-1.1, 1.1)
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.set_xlabel('Real(Γ)', fontsize=12, fontweight='bold')
    ax.set_ylabel('Imag(Γ)', fontsize=12, fontweight='bold')
    ax.set_title(title, fontsize=14, fontweight='bold')
    
    return fig, ax


def impedance_to_gamma(z, z0=50):
    """Convert impedance to reflection coefficient"""
    return (z - z0) / (z + z0)


def gamma_to_impedance(gamma, z0=50):
    """Convert reflection coefficient to impedance"""
    return z0 * (1 + gamma) / (1 - gamma)


# ============================================================================
# LOAD-PULL CONTOUR PLOTTING
# ============================================================================

def plot_loadpull_contours(gamma_real, gamma_imag, performance, 
                           levels=None, title="Load-Pull Contours",
                           metric_name="Pout (dBm)", optimal_point=None):
    """
    Plot load-pull contours on Smith chart
    
    Args:
        gamma_real: Real part of Γ (1D array of measured points)
        gamma_imag: Imaginary part of Γ (1D array)
        performance: Performance metric at each point (1D array)
        levels: Contour levels (if None, auto-generate)
        title: Plot title
        metric_name: Name of performance metric
        optimal_point: (gamma_real, gamma_imag) of optimal impedance
    
    Returns:
        fig, ax: Matplotlib figure and axis objects
    """
    fig, ax = plot_smith_chart(title=title, show_grid=True)
    
    # Create grid for interpolation
    grid_res = 200
    grid_x = np.linspace(-1, 1, grid_res)
    grid_y = np.linspace(-1, 1, grid_res)
    grid_X, grid_Y = np.meshgrid(grid_x, grid_y)
    
    # Interpolate performance data onto grid
    grid_perf = griddata((gamma_real, gamma_imag), performance, 
                         (grid_X, grid_Y), method='cubic')
    
    # Mask points outside Smith chart
    mask = grid_X**2 + grid_Y**2 > 1
    grid_perf[mask] = np.nan
    
    # Auto-generate levels if not provided
    if levels is None:
        perf_range = np.nanmax(grid_perf) - np.nanmin(grid_perf)
        levels = np.linspace(np.nanmin(grid_perf) + perf_range*0.1, 
                            np.nanmax(grid_perf), 10)
    
    # Filled contours
    contourf = ax.contourf(grid_X, grid_Y, grid_perf, levels=levels, 
                          cmap='RdYlGn', alpha=0.6, extend='both')
    
    # Contour lines
    contour = ax.contour(grid_X, grid_Y, grid_perf, levels=levels, 
                        colors='black', linewidths=0.8, alpha=0.7)
    ax.clabel(contour, inline=True, fontsize=8, fmt='%.1f')
    
    # Colorbar
    cbar = plt.colorbar(contourf, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label(metric_name, fontsize=11, fontweight='bold')
    
    # Mark optimal point if provided
    if optimal_point is not None:
        ax.plot(optimal_point[0], optimal_point[1], 'r*', 
               markersize=20, markeredgecolor='white', markeredgewidth=1.5)
        ax.annotate('Optimal', optimal_point, xytext=(15, 15),
                   textcoords='offset points', fontsize=10, fontweight='bold',
                   color='red',
                   bbox=dict(boxstyle='round,pad=0.5', facecolor='white', edgecolor='red'))
    
    # Measured points
    ax.scatter(gamma_real, gamma_imag, s=20, c='blue', marker='x', linewidths=1)
    
    return fig, ax


# ============================================================================
# 3D PERFORMANCE SURFACE
# ============================================================================

def plot_performance_surface_3d(gamma_real, gamma_imag, performance,
                                title="PA Performance Surface"):
    """
    Create 3D surface plot of PA performance vs impedance
    
    Args:
        gamma_real, gamma_imag, performance: 2D arrays or 1D arrays to be gridded
        title: Plot title
    
    Returns:
        fig, ax: Matplotlib 3D figure and axis
    """
    from mpl_toolkits.mplot3d import Axes3D
    
    fig = plt.figure(figsize=(12, 9))
    ax = fig.add_subplot(111, projection='3d')
    
    # If 1D arrays, grid them
    if gamma_real.ndim == 1:
        grid_res = 50
        grid_x = np.linspace(-1, 1, grid_res)
        grid_y = np.linspace(-1, 1, grid_res)
        grid_X, grid_Y = np.meshgrid(grid_x, grid_y)
        
        grid_perf = griddata((gamma_real, gamma_imag), performance,
                            (grid_X, grid_Y), method='cubic')
        
        # Mask outside Smith chart
        mask = grid_X**2 + grid_Y**2 > 1
        grid_perf[mask] = np.nan
    else:
        grid_X, grid_Y, grid_perf = gamma_real, gamma_imag, performance
    
    # Surface plot
    surf = ax.plot_surface(grid_X, grid_Y, grid_perf, cmap='viridis',
                          alpha=0.8, edgecolor='none')
    
    # Smith chart boundary at z=min
    theta = np.linspace(0, 2*np.pi, 100)
    circle_x = np.cos(theta)
    circle_y = np.sin(theta)
    circle_z = np.ones_like(theta) * np.nanmin(grid_perf)
    ax.plot(circle_x, circle_y, circle_z, 'k-', linewidth=2)
    
    ax.set_xlabel('Real(Γ)', fontsize=11, fontweight='bold')
    ax.set_ylabel('Imag(Γ)', fontsize=11, fontweight='bold')
    ax.set_zlabel('Performance', fontsize=11, fontweight='bold')
    ax.set_title(title, fontsize=14, fontweight='bold')
    
    # Colorbar
    fig.colorbar(surf, ax=ax, shrink=0.5, aspect=10)
    
    return fig, ax


# ============================================================================
# HARMONIC BALANCE WAVEFORMS
# ============================================================================

def plot_voltage_current_waveforms(time_us, voltage_v, current_a,
                                   title="Voltage and Current Waveforms"):
    """
    Plot time-domain voltage and current waveforms
    
    Args:
        time_us: Time in microseconds
        voltage_v: Drain/collector voltage in Volts
        current_a: Drain/collector current in Amps
        title: Plot title
    
    Returns:
        fig, ax: Matplotlib figure with dual y-axis
    """
    fig, ax1 = plt.subplots(figsize=(12, 6))
    
    # Voltage on left y-axis
    color_v = 'tab:red'
    ax1.set_xlabel('Time (μs)', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Voltage (V)', color=color_v, fontsize=12, fontweight='bold')
    ax1.plot(time_us, voltage_v, color=color_v, linewidth=2, label='Voltage')
    ax1.tick_params(axis='y', labelcolor=color_v)
    ax1.grid(True, alpha=0.3)
    
    # Current on right y-axis
    ax2 = ax1.twinx()
    color_i = 'tab:blue'
    ax2.set_ylabel('Current (A)', color=color_i, fontsize=12, fontweight='bold')
    ax2.plot(time_us, current_a, color=color_i, linewidth=2, label='Current')
    ax2.tick_params(axis='y', labelcolor=color_i)
    
    # Calculate and display power dissipation
    power_w = voltage_v * current_a
    avg_power = np.mean(power_w)
    ax1.fill_between(time_us, 0, voltage_v, where=(current_a > 0), 
                     alpha=0.1, color='purple', label=f'P_diss (avg={avg_power:.1f}W)')
    
    # Title
    fig.suptitle(title, fontsize=14, fontweight='bold')
    
    # Legend
    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc='upper right')
    
    fig.tight_layout()
    return fig, (ax1, ax2)


# ============================================================================
# CONSTELLATION DIAGRAM
# ============================================================================

def plot_constellation(i_samples, q_samples, title="Constellation Diagram",
                       reference_constellation=None, evm_percent=None):
    """
    Plot I/Q constellation diagram
    
    Args:
        i_samples: In-phase component (array)
        q_samples: Quadrature component (array)
        title: Plot title
        reference_constellation: Ideal constellation points (complex array)
        evm_percent: EVM value to display
    
    Returns:
        fig, ax: Matplotlib figure and axis
    """
    fig, ax = plt.subplots(figsize=(8, 8))
    
    # Measured constellation
    ax.scatter(i_samples, q_samples, s=5, c='blue', alpha=0.3, label='Measured')
    
    # Reference constellation (if provided)
    if reference_constellation is not None:
        i_ref = np.real(reference_constellation)
        q_ref = np.imag(reference_constellation)
        ax.scatter(i_ref, q_ref, s=100, c='red', marker='x', 
                  linewidths=2, label='Ideal', zorder=10)
    
    # Axes through origin
    ax.axhline(y=0, color='k', linewidth=0.5)
    ax.axvline(x=0, color='k', linewidth=0.5)
    
    ax.set_xlabel('In-Phase (I)', fontsize=12, fontweight='bold')
    ax.set_ylabel('Quadrature (Q)', fontsize=12, fontweight='bold')
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10)
    
    # Add EVM annotation
    if evm_percent is not None:
        ax.text(0.05, 0.95, f'EVM = {evm_percent:.2f}%', 
               transform=ax.transAxes, fontsize=12, fontweight='bold',
               verticalalignment='top',
               bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    ax.set_title(title, fontsize=14, fontweight='bold')
    fig.tight_layout()
    return fig, ax


# ============================================================================
# SPECTRUM PLOT
# ============================================================================

def plot_spectrum(freq_mhz, power_dbm, title="RF Spectrum",
                  center_freq_mhz=None, channel_bw_mhz=None, 
                  aclr_offsets_mhz=None):
    """
    Plot RF spectrum with optional ACLR measurement markers
    
    Args:
        freq_mhz: Frequency in MHz (array)
        power_dbm: Power in dBm (array)
        title: Plot title
        center_freq_mhz: Center frequency (for marking)
        channel_bw_mhz: Channel bandwidth (for shading)
        aclr_offsets_mhz: List of ACLR offset frequencies [lower, upper]
    
    Returns:
        fig, ax: Matplotlib figure and axis
    """
    fig, ax = plt.subplots(figsize=(12, 6))
    
    ax.plot(freq_mhz, power_dbm, 'b-', linewidth=1.5)
    ax.fill_between(freq_mhz, -150, power_dbm, alpha=0.3)
    
    # Mark center frequency and channel
    if center_freq_mhz is not None:
        ax.axvline(center_freq_mhz, color='r', linestyle='--', linewidth=1.5, label='Center')
        
        if channel_bw_mhz is not None:
            f_low = center_freq_mhz - channel_bw_mhz/2
            f_high = center_freq_mhz + channel_bw_mhz/2
            ax.axvspan(f_low, f_high, alpha=0.2, color='green', label='Channel BW')
    
    # Mark ACLR measurement windows
    if aclr_offsets_mhz is not None and center_freq_mhz is not None:
        for offset in aclr_offsets_mhz:
            f_aclr = center_freq_mhz + offset
            ax.axvline(f_aclr, color='orange', linestyle=':', linewidth=1.5)
            # Shade ACLR measurement window (assuming ±channel_bw/2)
            if channel_bw_mhz is not None:
                ax.axvspan(f_aclr - channel_bw_mhz/2, f_aclr + channel_bw_mhz/2,
                          alpha=0.15, color='red')
    
    ax.set_xlabel('Frequency (MHz)', fontsize=12, fontweight='bold')
    ax.set_ylabel('Power (dBm)', fontsize=12, fontweight='bold')
    ax.set_title(title, fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10)
    
    fig.tight_layout()
    return fig, ax


# ============================================================================
# EXAMPLE DATA GENERATORS
# ============================================================================

def generate_example_loadpull_data(n_points=100):
    """Generate synthetic load-pull data for testing"""
    # Random points on Smith chart
    r = np.random.uniform(0, 0.9, n_points)
    theta = np.random.uniform(0, 2*np.pi, n_points)
    gamma_real = r * np.cos(theta)
    gamma_imag = r * np.sin(theta)
    
    # Performance decreases with distance from optimal point
    optimal_gamma = 0.3 + 0.2j
    distance = np.abs((gamma_real + 1j*gamma_imag) - optimal_gamma)
    performance = 43 - 15 * distance**2  # Pout in dBm
    
    return gamma_real, gamma_imag, performance


def generate_example_waveforms():
    """Generate example voltage/current waveforms for Class AB PA"""
    t = np.linspace(0, 3, 1000)  # 3 periods
    omega = 2 * np.pi
    
    # Voltage (clipped sine wave)
    vdd = 28
    v_swing = 25
    voltage = vdd + v_swing * np.sin(omega * t)
    voltage = np.clip(voltage, 3, 2*vdd)  # Clip at knee and supply
    
    # Current (half-sine, Class AB)
    i_max = 3.0
    current = i_max * np.maximum(0, np.sin(omega * t - 0.1))**1.5
    
    return t, voltage, current


# ============================================================================
# MAIN EXAMPLE
# ============================================================================

if __name__ == "__main__":
    print("PA Figure Generation Scripts")
    print("============================\n")
    
    # Example 1: Smith chart with impedances
    print("Generating Smith chart example...")
    z_load = np.array([10+5j, 15+10j, 20-5j, 50+0j])
    labels = ['Zopt_Power', 'Zopt_PAE', 'Z_measured', '50Ω']
    fig, ax = plot_smith_chart(impedances=z_load, labels=labels, 
                               title="Load Impedance Optimization")
    plt.savefig('smith_chart_example.png', dpi=300, bbox_inches='tight')
    print("  Saved: smith_chart_example.png\n")
    
    # Example 2: Load-pull contours
    print("Generating load-pull contours...")
    gr, gi, perf = generate_example_loadpull_data(200)
    optimal_pt = (0.3, 0.2)
    fig, ax = plot_loadpull_contours(gr, gi, perf, 
                                     optimal_point=optimal_pt,
                                     title="Power Load-Pull @ 3.5 GHz",
                                     metric_name="Pout (dBm)")
    plt.savefig('loadpull_contours_example.png', dpi=300, bbox_inches='tight')
    print("  Saved: loadpull_contours_example.png\n")
    
    # Example 3: Voltage/current waveforms
    print("Generating waveform plot...")
    t, v, i = generate_example_waveforms()
    fig, ax = plot_voltage_current_waveforms(t, v, i,
                                             title="Class AB PA Waveforms @ 3.5 GHz")
    plt.savefig('waveforms_example.png', dpi=300, bbox_inches='tight')
    print("  Saved: waveforms_example.png\n")
    
    # Example 4: Constellation
    print("Generating constellation diagram...")
    # 256-QAM reference
    qam_order = 16  # Simplified for example
    ref_const = np.array([complex(i, q) for i in range(-int(np.sqrt(qam_order)/2), int(np.sqrt(qam_order)/2))
                         for q in range(-int(np.sqrt(qam_order)/2), int(np.sqrt(qam_order)/2))])
    # Add noise to simulate measured
    measured = []
    for symbol in ref_const:
        for _ in range(50):
            noise = 0.1 * (np.random.randn() + 1j * np.random.randn())
            measured.append(symbol + noise)
    measured = np.array(measured)
    
    fig, ax = plot_constellation(np.real(measured), np.imag(measured),
                                 reference_constellation=ref_const,
                                 evm_percent=2.5,
                                 title="256-QAM Constellation (Simulated)")
    plt.savefig('constellation_example.png', dpi=300, bbox_inches='tight')
    print("  Saved: constellation_example.png\n")
    
    print("All example plots generated successfully!")
    print("\nUsage:")
    print("  Import this module and use the plotting functions with your data.")
    print("  Example: from plot_pa_figures_python import plot_smith_chart")

