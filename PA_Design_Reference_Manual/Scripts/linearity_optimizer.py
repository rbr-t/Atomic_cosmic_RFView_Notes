#!/usr/bin/env python3
"""
PA Linearity and Multi-Objective Optimizer
===========================================

This script implements optimization algorithms for PA design with focus on:
1. Linearity (IM3, ACPR, EVM)
2. Efficiency (PAE)
3. Output Power
4. Manufacturing Yield
5. Cost

Includes:
- Sweet spot finder for optimal bias/load
- Multi-objective Genetic Algorithm
- Pareto front analysis
- Trade-off visualization
- Manufacturing yield prediction

Author: PA Design Reference Manual Project
Date: February 1, 2026
"""

import numpy as np
import matplotlib.pyplot as plt
from scipy.optimize import differential_evolution
from scipy.stats import norm
import pandas as pd
from dataclasses import dataclass
from typing import List, Tuple, Dict
import warnings
warnings.filterwarnings('ignore')

# ============================================================================
# DATA STRUCTURES
# ============================================================================

@dataclass
class PASpecs:
    """PA Design Specifications"""
    freq_ghz: float
    pout_dbm: float
    pae_min_percent: float
    im3_max_dbc: float
    acpr_max_dbc: float = -45.0
    evm_max_percent: float = 3.0
    gain_db: float = 15.0
    vdd_v: float = 28.0
    
@dataclass
class PADesign:
    """PA Design Parameters"""
    transistor_width_um: float
    bias_iq_ma: float
    load_z_real_ohm: float
    load_z_imag_ohm: float
    harmonic_tuning: bool
    input_match_optimize: bool
    
@dataclass
class PAPerformance:
    """PA Performance Metrics"""
    pout_dbm: float
    pae_percent: float
    im3_dbc: float
    acpr_dbc: float
    gain_db: float
    p1db_dbm: float
    cost_usd: float
    yield_percent: float

# ============================================================================
# PA SIMULATION ENGINE (Simplified Model)
# ============================================================================

class PASimulator:
    """Simplified PA performance simulator for optimization"""
    
    def __init__(self, specs: PASpecs):
        self.specs = specs
        
    def simulate_performance(self, design: PADesign) -> PAPerformance:
        """
        Simulate PA performance based on design parameters
        
        Note: This is a simplified analytical model. In real applications,
        replace with actual EM/circuit simulation or measured data.
        """
        
        # Extract design parameters
        W = design.transistor_width_um
        Iq = design.bias_iq_ma
        Zr = design.load_z_real_ohm
        Zi = design.load_z_imag_ohm
        
        # Calculate bias class factor (A=1.0, AB=0.7, B=0.5)
        bias_class_factor = Iq / 100.0  # Normalized to 100mA
        
        # Output Power Model
        # Pout increases with transistor width and optimal load
        Zopt = 50.0  # Optimal load impedance
        Z_penalty = abs(Zr - Zopt) / Zopt
        pout_dbm = (
            10 * np.log10(W / 100) +  # Width contribution
            self.specs.pout_dbm +
            10 * np.log10(self.specs.vdd_v / 28) -  # Voltage scaling
            2 * Z_penalty  # Load mismatch penalty
        )
        
        # PAE Model (efficiency vs bias class trade-off)
        # Class A: high linearity, low efficiency
        # Class B: low linearity, high efficiency
        max_pae = 70.0
        pae_percent = max_pae * (1 - bias_class_factor) * (1 - 0.5 * Z_penalty)
        
        # Linearity Model (IM3)
        # Better linearity with Class A bias (higher Iq)
        # Worse linearity near compression
        backoff_db = 3.0  # Typical operating backoff
        im3_best = -55.0  # Best achievable IM3
        im3_dbc = im3_best + 20 * (1 - bias_class_factor) + 5 * Z_penalty
        
        # ACPR (correlated with IM3)
        acpr_dbc = im3_dbc - 5.0
        
        # Gain Model
        gain_db = self.specs.gain_db - 0.5 * Z_penalty
        
        # P1dB (compression point)
        p1db_dbm = pout_dbm + 1.0
        
        # Cost Model
        cost_base = 5.0  # Base component cost
        cost_width = W / 100 * 2.0  # Larger transistor = higher cost
        cost_tuning = 3.0 if design.harmonic_tuning else 0.0
        cost_usd = cost_base + cost_width + cost_tuning
        
        # Yield Model (simplified - affected by tight specs)
        margin_pout = pout_dbm - self.specs.pout_dbm
        margin_pae = pae_percent - self.specs.pae_min_percent
        margin_im3 = im3_dbc - self.specs.im3_max_dbc
        
        # Yield drops if margins are small
        yield_factors = [
            1.0 - np.exp(-margin_pout / 2.0) if margin_pout > 0 else 0.5,
            1.0 - np.exp(-margin_pae / 5.0) if margin_pae > 0 else 0.5,
            1.0 - np.exp(-abs(margin_im3) / 3.0) if margin_im3 < 0 else 0.5,
        ]
        yield_percent = 100 * np.prod(yield_factors)
        
        return PAPerformance(
            pout_dbm=pout_dbm,
            pae_percent=pae_percent,
            im3_dbc=im3_dbc,
            acpr_dbc=acpr_dbc,
            gain_db=gain_db,
            p1db_dbm=p1db_dbm,
            cost_usd=cost_usd,
            yield_percent=yield_percent
        )

# ============================================================================
# SWEET SPOT FINDER
# ============================================================================

class SweetSpotFinder:
    """Find optimal operating point for best linearity-efficiency trade-off"""
    
    def __init__(self, simulator: PASimulator):
        self.sim = simulator
        
    def find_sweet_spot(self, 
                       transistor_width: float = 200.0,
                       iq_range: Tuple[float, float] = (10, 100),
                       zl_range: Tuple[float, float] = (20, 100),
                       n_samples: int = 50) -> Tuple[PADesign, PAPerformance, pd.DataFrame]:
        """
        Sweep bias current and load impedance to find IM3 sweet spot
        
        Args:
            transistor_width: Fixed transistor width (um)
            iq_range: (min, max) bias current range (mA)
            zl_range: (min, max) load impedance range (Ohm)
            n_samples: Number of samples per dimension
            
        Returns:
            optimal_design, optimal_performance, results_dataframe
        """
        
        print("=" * 60)
        print("SWEET SPOT FINDER - Linearity Optimization")
        print("=" * 60)
        
        # Create search grid
        iq_vals = np.linspace(iq_range[0], iq_range[1], n_samples)
        zl_vals = np.linspace(zl_range[0], zl_range[1], n_samples)
        
        results = []
        
        print(f"\nSearching {n_samples}x{n_samples} = {n_samples**2} design points...")
        
        for i, iq in enumerate(iq_vals):
            for j, zl in enumerate(zl_vals):
                design = PADesign(
                    transistor_width_um=transistor_width,
                    bias_iq_ma=iq,
                    load_z_real_ohm=zl,
                    load_z_imag_ohm=0.0,
                    harmonic_tuning=False,
                    input_match_optimize=True
                )
                
                perf = self.sim.simulate_performance(design)
                
                # Calculate Figure of Merit (FOM)
                # Prioritize: linearity > efficiency > power
                fom = (
                    -perf.im3_dbc * 2.0 +  # Lower IM3 is better (more negative)
                    perf.pae_percent * 0.5 +  # Higher PAE is better
                    perf.pout_dbm * 0.3  # Higher Pout is better
                )
                
                results.append({
                    'iq_ma': iq,
                    'zl_ohm': zl,
                    'pout_dbm': perf.pout_dbm,
                    'pae_percent': perf.pae_percent,
                    'im3_dbc': perf.im3_dbc,
                    'gain_db': perf.gain_db,
                    'cost_usd': perf.cost_usd,
                    'yield_percent': perf.yield_percent,
                    'fom': fom
                })
            
            if (i + 1) % 10 == 0:
                print(f"  Progress: {(i+1)*100//n_samples}%")
        
        df = pd.DataFrame(results)
        
        # Find optimal point
        best_idx = df['fom'].idxmax()
        optimal = df.iloc[best_idx]
        
        optimal_design = PADesign(
            transistor_width_um=transistor_width,
            bias_iq_ma=optimal['iq_ma'],
            load_z_real_ohm=optimal['zl_ohm'],
            load_z_imag_ohm=0.0,
            harmonic_tuning=False,
            input_match_optimize=True
        )
        
        optimal_perf = PAPerformance(
            pout_dbm=optimal['pout_dbm'],
            pae_percent=optimal['pae_percent'],
            im3_dbc=optimal['im3_dbc'],
            acpr_dbc=optimal['im3_dbc'] - 5.0,
            gain_db=optimal['gain_db'],
            p1db_dbm=optimal['pout_dbm'] + 1.0,
            cost_usd=optimal['cost_usd'],
            yield_percent=optimal['yield_percent']
        )
        
        print("\n" + "=" * 60)
        print("SWEET SPOT FOUND:")
        print("=" * 60)
        print(f"  Bias Current (Iq): {optimal['iq_ma']:.1f} mA")
        print(f"  Load Impedance:    {optimal['zl_ohm']:.1f} Ω")
        print(f"  Output Power:      {optimal['pout_dbm']:.2f} dBm")
        print(f"  PAE:              {optimal['pae_percent']:.1f} %")
        print(f"  IM3:              {optimal['im3_dbc']:.1f} dBc")
        print(f"  Figure of Merit:   {optimal['fom']:.2f}")
        print("=" * 60 + "\n")
        
        return optimal_design, optimal_perf, df

# ============================================================================
# PARETO FRONT ANALYZER
# ============================================================================

class ParetoAnalyzer:
    """Identify Pareto-optimal designs for multi-objective optimization"""
    
    @staticmethod
    def find_pareto_front(designs: pd.DataFrame, 
                          objectives: List[str],
                          maximize: List[bool]) -> pd.DataFrame:
        """
        Find Pareto-optimal solutions
        
        Args:
            designs: DataFrame with design parameters and objectives
            objectives: List of column names to optimize
            maximize: List of bool (True=maximize, False=minimize) for each objective
            
        Returns:
            DataFrame containing only Pareto-optimal designs
        """
        
        # Convert to numpy array (make a copy to allow modifications)
        obj_matrix = designs[objectives].values.copy()
        
        # Flip sign for minimization objectives
        for i, should_max in enumerate(maximize):
            if not should_max:
                obj_matrix[:, i] = -obj_matrix[:, i]
        
        # Find Pareto front
        is_pareto = np.ones(len(obj_matrix), dtype=bool)
        
        for i, point in enumerate(obj_matrix):
            if is_pareto[i]:
                # Check if any other point dominates this one
                is_pareto[is_pareto] = np.any(
                    obj_matrix[is_pareto] > point, axis=1
                )
                is_pareto[i] = True  # Keep current point
        
        pareto_designs = designs[is_pareto].copy()
        pareto_designs['pareto_optimal'] = True
        
        print(f"\nPareto Front Analysis:")
        print(f"  Total designs: {len(designs)}")
        print(f"  Pareto-optimal: {len(pareto_designs)} ({100*len(pareto_designs)/len(designs):.1f}%)")
        
        return pareto_designs

# ============================================================================
# MULTI-OBJECTIVE GENETIC ALGORITHM
# ============================================================================

class MultiObjectiveOptimizer:
    """Genetic Algorithm for PA design optimization"""
    
    def __init__(self, simulator: PASimulator, specs: PASpecs):
        self.sim = simulator
        self.specs = specs
        
    def optimize(self, 
                 weights: Dict[str, float],
                 generations: int = 100,
                 population: int = 50,
                 verbose: bool = True) -> Tuple[PADesign, PAPerformance]:
        """
        Multi-objective optimization using Differential Evolution
        
        Args:
            weights: Dictionary of objective weights
                     e.g., {'pae': 0.3, 'im3': 0.5, 'pout': 0.2}
            generations: Number of generations
            population: Population size
            verbose: Print progress
            
        Returns:
            optimal_design, optimal_performance
        """
        
        if verbose:
            print("\n" + "=" * 60)
            print("MULTI-OBJECTIVE GENETIC ALGORITHM")
            print("=" * 60)
            print(f"  Generations: {generations}")
            print(f"  Population:  {population}")
            print(f"  Weights:     {weights}")
            print("=" * 60 + "\n")
        
        # Define bounds for design variables
        bounds = [
            (50, 500),    # transistor_width_um
            (10, 100),    # bias_iq_ma
            (20, 100),    # load_z_real_ohm
            (-20, 20),    # load_z_imag_ohm
        ]
        
        def objective_function(x):
            """Fitness function to minimize (negative of weighted score)"""
            design = PADesign(
                transistor_width_um=x[0],
                bias_iq_ma=x[1],
                load_z_real_ohm=x[2],
                load_z_imag_ohm=x[3],
                harmonic_tuning=False,
                input_match_optimize=True
            )
            
            perf = self.sim.simulate_performance(design)
            
            # Calculate penalties for not meeting specs
            penalty = 0.0
            
            if perf.im3_dbc > self.specs.im3_max_dbc:
                penalty += 1000 * (perf.im3_dbc - self.specs.im3_max_dbc)
            
            if perf.pout_dbm < self.specs.pout_dbm:
                penalty += 1000 * (self.specs.pout_dbm - perf.pout_dbm)
            
            if perf.pae_percent < self.specs.pae_min_percent:
                penalty += 500 * (self.specs.pae_min_percent - perf.pae_percent)
            
            # Weighted multi-objective score (to maximize)
            score = (
                weights.get('pae', 0.3) * perf.pae_percent / 70.0 +  # Normalized to max PAE
                weights.get('im3', 0.4) * (-perf.im3_dbc) / 60.0 +  # Normalized to best IM3
                weights.get('pout', 0.2) * (perf.pout_dbm - 30) / 20.0 +  # Normalized range
                weights.get('cost', 0.1) * (1 - perf.cost_usd / 20.0)  # Normalized cost
            )
            
            # Return negative score (since we minimize)
            return -(score - penalty)
        
        # Run differential evolution
        result = differential_evolution(
            objective_function,
            bounds,
            maxiter=generations,
            popsize=population,
            seed=42,
            disp=verbose,
            polish=True
        )
        
        # Extract optimal design
        optimal_design = PADesign(
            transistor_width_um=result.x[0],
            bias_iq_ma=result.x[1],
            load_z_real_ohm=result.x[2],
            load_z_imag_ohm=result.x[3],
            harmonic_tuning=False,
            input_match_optimize=True
        )
        
        optimal_perf = self.sim.simulate_performance(optimal_design)
        
        if verbose:
            print("\n" + "=" * 60)
            print("OPTIMIZATION COMPLETE")
            print("=" * 60)
            print(f"  Transistor Width:  {optimal_design.transistor_width_um:.1f} μm")
            print(f"  Bias Current:      {optimal_design.bias_iq_ma:.1f} mA")
            print(f"  Load Impedance:    {optimal_design.load_z_real_ohm:.1f} + j{optimal_design.load_z_imag_ohm:.1f} Ω")
            print(f"\n  Performance:")
            print(f"    Pout:  {optimal_perf.pout_dbm:.2f} dBm")
            print(f"    PAE:   {optimal_perf.pae_percent:.1f} %")
            print(f"    IM3:   {optimal_perf.im3_dbc:.1f} dBc")
            print(f"    Cost:  ${optimal_perf.cost_usd:.2f}")
            print(f"    Yield: {optimal_perf.yield_percent:.1f} %")
            print("=" * 60 + "\n")
        
        return optimal_design, optimal_perf

# ============================================================================
# VISUALIZATION TOOLS
# ============================================================================

class PAVisualizer:
    """Generate trade-off plots and visualizations"""
    
    @staticmethod
    def plot_tradeoffs(df: pd.DataFrame, specs: PASpecs, save_path: str = None):
        """
        Generate comprehensive trade-off analysis plots
        
        Args:
            df: DataFrame with design sweep results
            specs: PA specifications
            save_path: Optional path to save figure
        """
        
        fig = plt.figure(figsize=(16, 12))
        
        # Plot 1: PAE vs IM3 (Linearity-Efficiency Trade-off)
        ax1 = plt.subplot(2, 3, 1)
        scatter1 = ax1.scatter(df['im3_dbc'], df['pae_percent'], 
                              c=df['pout_dbm'], cmap='viridis', 
                              alpha=0.6, s=50)
        ax1.axvline(specs.im3_max_dbc, color='r', linestyle='--', 
                   linewidth=2, label='IM3 Spec')
        ax1.axhline(specs.pae_min_percent, color='orange', linestyle='--', 
                   linewidth=2, label='PAE Spec')
        ax1.set_xlabel('IM3 (dBc)', fontsize=12, fontweight='bold')
        ax1.set_ylabel('PAE (%)', fontsize=12, fontweight='bold')
        ax1.set_title('Linearity vs Efficiency Trade-off', 
                     fontsize=14, fontweight='bold')
        ax1.grid(True, alpha=0.3)
        ax1.legend()
        plt.colorbar(scatter1, ax=ax1, label='Pout (dBm)')
        
        # Plot 2: Pout vs IM3 (Power-Linearity Trade-off)
        ax2 = plt.subplot(2, 3, 2)
        scatter2 = ax2.scatter(df['pout_dbm'], df['im3_dbc'], 
                              c=df['iq_ma'], cmap='plasma', 
                              alpha=0.6, s=50)
        ax2.axvline(specs.pout_dbm, color='r', linestyle='--', 
                   linewidth=2, label='Pout Spec')
        ax2.axhline(specs.im3_max_dbc, color='orange', linestyle='--', 
                   linewidth=2, label='IM3 Spec')
        ax2.set_xlabel('Output Power (dBm)', fontsize=12, fontweight='bold')
        ax2.set_ylabel('IM3 (dBc)', fontsize=12, fontweight='bold')
        ax2.set_title('Power vs Linearity Trade-off', 
                     fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3)
        ax2.legend()
        plt.colorbar(scatter2, ax=ax2, label='Iq (mA)')
        
        # Plot 3: 3D Performance Triangle
        ax3 = plt.subplot(2, 3, 3)
        # Normalize to 0-1 for triangle plot
        pae_norm = df['pae_percent'] / df['pae_percent'].max()
        im3_norm = -df['im3_dbc'] / -df['im3_dbc'].min()
        pout_norm = df['pout_dbm'] / df['pout_dbm'].max()
        
        scatter3 = ax3.scatter(im3_norm, pae_norm, 
                              c=pout_norm, cmap='RdYlGn', 
                              alpha=0.6, s=50)
        ax3.set_xlabel('Linearity (normalized)', fontsize=12, fontweight='bold')
        ax3.set_ylabel('Efficiency (normalized)', fontsize=12, fontweight='bold')
        ax3.set_title('Performance Triangle', 
                     fontsize=14, fontweight='bold')
        ax3.grid(True, alpha=0.3)
        plt.colorbar(scatter3, ax=ax3, label='Power (norm)')
        
        # Plot 4: IM3 Contour Map (vs Iq and ZL)
        ax4 = plt.subplot(2, 3, 4)
        pivot = df.pivot_table(values='im3_dbc', 
                               index='zl_ohm', 
                               columns='iq_ma')
        contour = ax4.contourf(pivot.columns, pivot.index, pivot.values, 
                               levels=20, cmap='RdYlGn_r')
        ax4.set_xlabel('Bias Current (mA)', fontsize=12, fontweight='bold')
        ax4.set_ylabel('Load Impedance (Ω)', fontsize=12, fontweight='bold')
        ax4.set_title('IM3 Design Space (dBc)', 
                     fontsize=14, fontweight='bold')
        plt.colorbar(contour, ax=ax4, label='IM3 (dBc)')
        
        # Plot 5: PAE Contour Map (vs Iq and ZL)
        ax5 = plt.subplot(2, 3, 5)
        pivot_pae = df.pivot_table(values='pae_percent', 
                                    index='zl_ohm', 
                                    columns='iq_ma')
        contour2 = ax5.contourf(pivot_pae.columns, pivot_pae.index, pivot_pae.values, 
                                levels=20, cmap='viridis')
        ax5.set_xlabel('Bias Current (mA)', fontsize=12, fontweight='bold')
        ax5.set_ylabel('Load Impedance (Ω)', fontsize=12, fontweight='bold')
        ax5.set_title('PAE Design Space (%)', 
                     fontsize=14, fontweight='bold')
        plt.colorbar(contour2, ax=ax5, label='PAE (%)')
        
        # Plot 6: Yield vs Performance Margin
        ax6 = plt.subplot(2, 3, 6)
        df['im3_margin'] = df['im3_dbc'] - specs.im3_max_dbc
        scatter6 = ax6.scatter(df['im3_margin'], df['yield_percent'], 
                              c=df['pae_percent'], cmap='coolwarm', 
                              alpha=0.6, s=50)
        ax6.axvline(0, color='r', linestyle='--', linewidth=2, label='Spec Limit')
        ax6.set_xlabel('IM3 Margin (dB)', fontsize=12, fontweight='bold')
        ax6.set_ylabel('Predicted Yield (%)', fontsize=12, fontweight='bold')
        ax6.set_title('Manufacturing Yield Analysis', 
                     fontsize=14, fontweight='bold')
        ax6.grid(True, alpha=0.3)
        ax6.legend()
        plt.colorbar(scatter6, ax=ax6, label='PAE (%)')
        
        plt.tight_layout()
        
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            print(f"\nTrade-off plots saved to: {save_path}")
        
        plt.show()
    
    @staticmethod
    def plot_pareto_front(df: pd.DataFrame, pareto_df: pd.DataFrame):
        """
        Visualize Pareto front for PAE vs IM3
        
        Args:
            df: All designs
            pareto_df: Pareto-optimal designs only
        """
        
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
        
        # Plot 1: PAE vs IM3 with Pareto front
        ax1.scatter(df['im3_dbc'], df['pae_percent'], 
                   c='lightgray', alpha=0.4, s=30, label='All Designs')
        ax1.scatter(pareto_df['im3_dbc'], pareto_df['pae_percent'], 
                   c='red', marker='*', s=200, 
                   edgecolors='darkred', linewidths=2,
                   label='Pareto Optimal', zorder=5)
        ax1.set_xlabel('IM3 (dBc)', fontsize=12, fontweight='bold')
        ax1.set_ylabel('PAE (%)', fontsize=12, fontweight='bold')
        ax1.set_title('Pareto Front: Efficiency vs Linearity', 
                     fontsize=14, fontweight='bold')
        ax1.grid(True, alpha=0.3)
        ax1.legend(fontsize=11)
        
        # Plot 2: 3D scatter (Pout, PAE, IM3)
        from mpl_toolkits.mplot3d import Axes3D
        ax2 = fig.add_subplot(122, projection='3d')
        ax2.scatter(df['pout_dbm'], df['pae_percent'], -df['im3_dbc'], 
                   c='lightgray', alpha=0.3, s=20, label='All Designs')
        ax2.scatter(pareto_df['pout_dbm'], pareto_df['pae_percent'], 
                   -pareto_df['im3_dbc'], 
                   c='red', marker='*', s=200, 
                   edgecolors='darkred', linewidths=2,
                   label='Pareto Optimal', zorder=5)
        ax2.set_xlabel('Pout (dBm)', fontsize=10, fontweight='bold')
        ax2.set_ylabel('PAE (%)', fontsize=10, fontweight='bold')
        ax2.set_zlabel('Linearity (-IM3)', fontsize=10, fontweight='bold')
        ax2.set_title('3D Pareto Front', fontsize=14, fontweight='bold')
        ax2.legend()
        
        plt.tight_layout()
        plt.show()

# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main():
    """Demonstrate PA optimization workflow"""
    
    print("\n" + "=" * 70)
    print(" PA LINEARITY & MULTI-OBJECTIVE OPTIMIZER")
    print(" Enhanced for Manufacturing and Trade-off Analysis")
    print("=" * 70)
    
    # Define specifications
    specs = PASpecs(
        freq_ghz=3.5,
        pout_dbm=43.0,
        pae_min_percent=45.0,
        im3_max_dbc=-40.0,
        acpr_max_dbc=-45.0,
        gain_db=15.0,
        vdd_v=28.0
    )
    
    print("\nTarget Specifications:")
    print(f"  Frequency:     {specs.freq_ghz} GHz")
    print(f"  Output Power:  {specs.pout_dbm} dBm")
    print(f"  PAE:          >{specs.pae_min_percent} %")
    print(f"  IM3:          <{specs.im3_max_dbc} dBc (CRITICAL)")
    print(f"  ACPR:         <{specs.acpr_max_dbc} dBc")
    print(f"  Supply:        {specs.vdd_v} V")
    
    # Initialize simulator
    simulator = PASimulator(specs)
    
    # ========================================================================
    # METHOD 1: SWEET SPOT FINDER
    # ========================================================================
    print("\n\n" + "=" * 70)
    print(" METHOD 1: SWEET SPOT FINDER (Grid Search)")
    print("=" * 70)
    
    finder = SweetSpotFinder(simulator)
    optimal_design1, optimal_perf1, sweep_results = finder.find_sweet_spot(
        transistor_width=200.0,
        iq_range=(20, 80),
        zl_range=(30, 80),
        n_samples=40
    )
    
    # ========================================================================
    # METHOD 2: PARETO FRONT ANALYSIS
    # ========================================================================
    print("\n" + "=" * 70)
    print(" METHOD 2: PARETO FRONT ANALYSIS")
    print("=" * 70)
    
    pareto_analyzer = ParetoAnalyzer()
    pareto_designs = pareto_analyzer.find_pareto_front(
        sweep_results,
        objectives=['pae_percent', 'im3_dbc'],
        maximize=[True, False]  # Maximize PAE, Minimize IM3 (more negative)
    )
    
    print("\nTop 5 Pareto-Optimal Designs:")
    print(pareto_designs.nlargest(5, 'fom')[
        ['iq_ma', 'zl_ohm', 'pout_dbm', 'pae_percent', 'im3_dbc', 'yield_percent']
    ].to_string(index=False))
    
    # ========================================================================
    # METHOD 3: MULTI-OBJECTIVE GA
    # ========================================================================
    print("\n\n" + "=" * 70)
    print(" METHOD 3: MULTI-OBJECTIVE GENETIC ALGORITHM")
    print("=" * 70)
    
    optimizer = MultiObjectiveOptimizer(simulator, specs)
    optimal_design2, optimal_perf2 = optimizer.optimize(
        weights={
            'im3': 0.5,   # Linearity is priority (50%)
            'pae': 0.3,   # Efficiency (30%)
            'pout': 0.15, # Power (15%)
            'cost': 0.05  # Cost (5%)
        },
        generations=50,
        population=30,
        verbose=True
    )
    
    # ========================================================================
    # VISUALIZATION
    # ========================================================================
    print("\n" + "=" * 70)
    print(" GENERATING TRADE-OFF VISUALIZATIONS")
    print("=" * 70)
    
    visualizer = PAVisualizer()
    
    # Generate comprehensive trade-off plots
    visualizer.plot_tradeoffs(sweep_results, specs, 
                             save_path='pa_tradeoff_analysis.png')
    
    # Generate Pareto front plots
    visualizer.plot_pareto_front(sweep_results, pareto_designs)
    
    # ========================================================================
    # FINAL RECOMMENDATIONS
    # ========================================================================
    print("\n" + "=" * 70)
    print(" DESIGN RECOMMENDATIONS")
    print("=" * 70)
    
    print("\n1. SWEET SPOT DESIGN (Grid Search):")
    print(f"   Iq = {optimal_design1.bias_iq_ma:.1f} mA, ZL = {optimal_design1.load_z_real_ohm:.1f} Ω")
    print(f"   → Pout = {optimal_perf1.pout_dbm:.2f} dBm, PAE = {optimal_perf1.pae_percent:.1f}%, IM3 = {optimal_perf1.im3_dbc:.1f} dBc")
    
    print("\n2. GA-OPTIMIZED DESIGN:")
    print(f"   W = {optimal_design2.transistor_width_um:.1f} μm, Iq = {optimal_design2.bias_iq_ma:.1f} mA")
    print(f"   ZL = {optimal_design2.load_z_real_ohm:.1f} + j{optimal_design2.load_z_imag_ohm:.1f} Ω")
    print(f"   → Pout = {optimal_perf2.pout_dbm:.2f} dBm, PAE = {optimal_perf2.pae_percent:.1f}%, IM3 = {optimal_perf2.im3_dbc:.1f} dBc")
    print(f"   → Cost = ${optimal_perf2.cost_usd:.2f}, Yield = {optimal_perf2.yield_percent:.1f}%")
    
    print("\n3. PARETO-OPTIMAL DESIGNS:")
    print(f"   {len(pareto_designs)} Pareto-optimal solutions identified")
    print(f"   Range: IM3 = [{pareto_designs['im3_dbc'].min():.1f}, {pareto_designs['im3_dbc'].max():.1f}] dBc")
    print(f"          PAE = [{pareto_designs['pae_percent'].min():.1f}, {pareto_designs['pae_percent'].max():.1f}] %")
    
    print("\n" + "=" * 70)
    print(" ANALYSIS COMPLETE - Review plots for detailed trade-offs")
    print("=" * 70 + "\n")

if __name__ == "__main__":
    main()
