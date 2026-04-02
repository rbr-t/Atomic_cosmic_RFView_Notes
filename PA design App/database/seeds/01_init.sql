-- PA Design App Database Initialization
-- Creates all necessary tables and indexes

-- Projects table
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    architecture_type VARCHAR(50),
    topology VARCHAR(50),
    frequency_min NUMERIC,
    frequency_max NUMERIC,
    frequency NUMERIC,
    target_pout NUMERIC,
    target_gain NUMERIC,
    target_pae NUMERIC,
    current_phase VARCHAR(50) DEFAULT 'concept',
    status VARCHAR(20) DEFAULT 'active',
    tags TEXT[],
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_phase ON projects(current_phase);
CREATE INDEX IF NOT EXISTS idx_projects_created ON projects(created_at DESC);

-- Datasets table
CREATE TABLE IF NOT EXISTS datasets (
    id UUID PRIMARY KEY,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50),
    format VARCHAR(20),
    file_path TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_datasets_project ON datasets(project_id);
CREATE INDEX IF NOT EXISTS idx_datasets_type ON datasets(type);

-- Tags table
CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    tag_name VARCHAR(100) NOT NULL,
    tag_value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(entity_type, entity_id, tag_name)
);

CREATE INDEX IF NOT EXISTS idx_tags_entity ON tags(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(tag_name);

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'designer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Agent logs table
CREATE TABLE IF NOT EXISTS agent_logs (
    id UUID PRIMARY KEY,
    agent_name VARCHAR(100) NOT NULL,
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    input_data JSONB,
    output_data JSONB,
    confidence NUMERIC,
    execution_time_ms INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_agent_logs_agent ON agent_logs(agent_name);
CREATE INDEX IF NOT EXISTS idx_agent_logs_project ON agent_logs(project_id);
CREATE INDEX IF NOT EXISTS idx_agent_logs_created ON agent_logs(created_at DESC);

-- Simulations table
CREATE TABLE IF NOT EXISTS simulations (
    id UUID PRIMARY KEY,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    tool VARCHAR(50),
    parameters JSONB,
    results JSONB,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_simulations_project ON simulations(project_id);
CREATE INDEX IF NOT EXISTS idx_simulations_status ON simulations(status);

-- Insert demo data
INSERT INTO projects (id, name, architecture_type, frequency, target_pout, current_phase, status)
VALUES 
    (gen_random_uuid(), '5G PA - 3.5GHz', 'Class-AB', 3.5, 43, 'simulation', 'active'),
    (gen_random_uuid(), 'WiFi 6E PA - 6GHz', 'Class-E', 6.0, 30, 'layout', 'active'),
    (gen_random_uuid(), 'Sub-6 GaN PA', 'Doherty', 2.4, 50, 'concept', 'planning')
ON CONFLICT DO NOTHING;

-- Create function for updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for projects table
DROP TRIGGER IF EXISTS update_projects_updated_at ON projects;
CREATE TRIGGER update_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
