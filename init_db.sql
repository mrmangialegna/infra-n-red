-- PostgreSQL Unified Schema
-- Platform data (ex-MongoDB functionality)
CREATE SCHEMA IF NOT EXISTS platform;

-- App data (shared PVC for containers)
CREATE SCHEMA IF NOT EXISTS apps;

-- Platform tables
CREATE TABLE platform.users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE platform.deployments (
    app_name VARCHAR(100) PRIMARY KEY,
    repo_url VARCHAR(500) NOT NULL,
    commit_sha VARCHAR(40) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE platform.app_configs (
    app_name VARCHAR(100) PRIMARY KEY,
    env_vars JSONB DEFAULT '{}',
    scaling JSONB DEFAULT '{"replicas": 2}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- App shared data table
CREATE TABLE apps.data (
    id SERIAL PRIMARY KEY,
    app_id VARCHAR(100) NOT NULL,
    key VARCHAR(255) NOT NULL,
    value JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(app_id, key)
);

-- Indexes for performance
CREATE INDEX idx_apps_data_app_id ON apps.data(app_id);
CREATE INDEX idx_apps_data_key ON apps.data(key);
CREATE INDEX idx_platform_deployments_status ON platform.deployments(status);

-- Example data access pattern for apps:
-- INSERT INTO apps.data (app_id, key, value) VALUES ('myapp', 'user:123', '{"name": "John", "email": "john@example.com"}');
-- SELECT value FROM apps.data WHERE app_id = 'myapp' AND key = 'user:123';
