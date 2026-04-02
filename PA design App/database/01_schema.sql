-- ============================================================
-- PA Lineup Database Schema
-- Version control and configuration storage
-- ============================================================

-- Table: pa_lineup_configurations
-- Stores complete lineup configurations with versioning
CREATE TABLE IF NOT EXISTS pa_lineup_configurations (
    config_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    version_number VARCHAR(20) NOT NULL,
    config_name VARCHAR(255) NOT NULL,
    description TEXT,
    architecture_type VARCHAR(100), -- 'single_doherty', 'dual_doherty', 'balanced', etc.
    components JSONB NOT NULL, -- Array of component definitions
    connections JSONB, -- Array of connection definitions
    groups JSONB, -- Component groupings
    tags TEXT[], -- Architecture tags
    created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    parent_config_id UUID REFERENCES pa_lineup_configurations(config_id), -- For version tracking
    UNIQUE(project_id, version_number)
);

-- Table: pa_lineup_calculations
-- Stores calculation results for each configuration
CREATE TABLE IF NOT EXISTS pa_lineup_calculations (
    calc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_id UUID REFERENCES pa_lineup_configurations(config_id) ON DELETE CASCADE,
    calculation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Input conditions
    input_power_dbm NUMERIC(10, 3),
    frequency_ghz NUMERIC(10, 3),
    
    -- Overall results
    total_gain_db NUMERIC(10, 3),
    output_power_dbm NUMERIC(10, 3),
    output_power_w NUMERIC(12, 6),
    system_pae_percent NUMERIC(10, 3),
    total_dc_power_w NUMERIC(12, 6),
    total_dissipation_w NUMERIC(12, 6),
    
    -- Stage-by-stage results
    stage_results JSONB, -- Detailed per-stage calculations
    
    -- Warnings and status
    compression_warnings TEXT[],
    thermal_warnings TEXT[],
    other_warnings TEXT[],
    overall_status VARCHAR(50), -- 'PASS', 'WARNING', 'FAIL'
    
    -- Rationale and notes
    calculation_rationale TEXT,
    design_notes TEXT,
    
    UNIQUE(config_id, calculation_timestamp)
);

-- Table: pa_lineup_component_library
-- User-defined component templates
CREATE TABLE IF NOT EXISTS pa_lineup_component_library (
    component_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(100),
    component_type VARCHAR(50) NOT NULL, -- 'transistor', 'matching', 'splitter', 'combiner'
    component_name VARCHAR(255) NOT NULL,
    manufacturer VARCHAR(100),
    part_number VARCHAR(100),
    technology VARCHAR(50),
    default_properties JSONB NOT NULL,
    datasheet_url TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, component_name)
);

-- Table: pa_lineup_trade_study
-- Trade-off analysis comparing multiple configurations
CREATE TABLE IF NOT EXISTS pa_lineup_trade_study (
    study_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    study_name VARCHAR(255) NOT NULL,
    description TEXT,
    config_ids UUID[], -- Array of configuration IDs being compared
    comparison_criteria JSONB, -- Weights for different metrics
    pareto_analysis JSONB, -- Pareto-optimal solutions
    recommendations TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(project_id, study_name)
);

-- Table: pa_lineup_reports
-- Generated reports for configurations
CREATE TABLE IF NOT EXISTS pa_lineup_reports (
    report_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_id UUID REFERENCES pa_lineup_configurations(config_id) ON DELETE CASCADE,
    calc_id UUID REFERENCES pa_lineup_calculations(calc_id) ON DELETE SET NULL,
    report_type VARCHAR(50), -- 'pdf', 'html', 'markdown'
    report_title VARCHAR(255),
    report_content TEXT, -- HTML or markdown content
    includes_diagram BOOLEAN DEFAULT TRUE,
    includes_calculations BOOLEAN DEFAULT TRUE,
    includes_rationale BOOLEAN DEFAULT TRUE,
    custom_notes TEXT,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    generated_by VARCHAR(100)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_pa_lineup_config_project ON pa_lineup_configurations(project_id);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_config_version ON pa_lineup_configurations(version_number);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_config_arch_type ON pa_lineup_configurations(architecture_type);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_config_tags ON pa_lineup_configurations USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_calc_config ON pa_lineup_calculations(config_id);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_calc_timestamp ON pa_lineup_calculations(calculation_timestamp);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_component_type ON pa_lineup_component_library(component_type);
CREATE INDEX IF NOT EXISTS idx_pa_lineup_trade_study_project ON pa_lineup_trade_study(project_id);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_pa_lineup_config_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pa_lineup_config_update_trigger
BEFORE UPDATE ON pa_lineup_configurations
FOR EACH ROW
EXECUTE FUNCTION update_pa_lineup_config_timestamp();

-- View: Latest configurations per project
CREATE OR REPLACE VIEW pa_lineup_latest_configs AS
SELECT DISTINCT ON (project_id)
    config_id,
    project_id,
    version_number,
    config_name,
    architecture_type,
    tags,
    created_at,
    updated_at
FROM pa_lineup_configurations
WHERE is_active = TRUE
ORDER BY project_id, created_at DESC;

-- View: Configuration summary with calculation results
CREATE OR REPLACE VIEW pa_lineup_config_summary AS
SELECT 
    c.config_id,
    c.project_id,
    c.version_number,
    c.config_name,
    c.architecture_type,
    c.tags,
    calc.total_gain_db,
    calc.system_pae_percent,
    calc.output_power_dbm,
    calc.total_dc_power_w,
    calc.overall_status,
    c.created_at
FROM pa_lineup_configurations c
LEFT JOIN LATERAL (
    SELECT * FROM pa_lineup_calculations
    WHERE config_id = c.config_id
    ORDER BY calculation_timestamp DESC
    LIMIT 1
) calc ON TRUE
WHERE c.is_active = TRUE
ORDER BY c.created_at DESC;

-- Insert demo data for component library
INSERT INTO pa_lineup_component_library (component_type, component_name, technology, default_properties, notes)
VALUES 
    ('transistor', 'GaN 100W', 'GaN', 
     '{"gain_db": 13, "pae": 65, "p1db_dbm": 50, "vdd": 28, "class": "AB"}',
     'High efficiency GaN HEMT for base station applications'),
    ('transistor', 'LDMOS 200W', 'LDMOS',
     '{"gain_db": 15, "pae": 55, "p1db_dbm": 53, "vdd": 28, "class": "AB"}',
     'Rugged LDMOS for macro base stations'),
    ('transistor', 'GaN 50W Driver', 'GaN',
     '{"gain_db": 18, "pae": 55, "p1db_dbm": 47, "vdd": 28, "class": "AB"}',
     'Driver stage GaN device'),
    ('matching', 'Low Loss Matching', 'Microstrip',
     '{"loss_db": 0.3, "vswr": 1.2, "type": "L-section"}',
     'Optimized for minimum loss'),
    ('splitter', 'Wilkinson 2-way', 'Hybrid',
     '{"n_way": 2, "loss_db": 0.25, "isolation_db": 25, "phase_balance_deg": 0.5}',
     'Standard Wilkinson power divider'),
    ('combiner', 'Doherty Combiner', 'Hybrid',
     '{"n_way": 2, "loss_db": 0.4, "efficiency": 95, "topology": "Doherty"}',
     'Doherty load modulation network')
ON CONFLICT (user_id, component_name) DO NOTHING;

COMMENT ON TABLE pa_lineup_configurations IS 'Stores complete PA lineup configurations with version control';
COMMENT ON TABLE pa_lineup_calculations IS 'Stores calculation results and rationale for each configuration';
COMMENT ON TABLE pa_lineup_component_library IS 'User-defined library of reusable components';
COMMENT ON TABLE pa_lineup_trade_study IS 'Trade-off analysis comparing multiple configurations';
COMMENT ON TABLE pa_lineup_reports IS 'Generated reports for configurations';
