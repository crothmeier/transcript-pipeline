-- PostgreSQL 16 Schema for AI Transcript Pipeline
-- Production deployment with vector similarity search
-- Optimized for 128GB RAM system with RAID10 storage

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Transcripts table: Core entity for audio/video transcript storage
CREATE TABLE transcripts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source TEXT NOT NULL,                          -- Original audio/video source identifier
    raw_content TEXT NOT NULL,                     -- Full transcript text
    summary TEXT,                                  -- AI-generated summary
    filepath TEXT UNIQUE NOT NULL,                 -- Unique path to source file
    conversation_id TEXT,                          -- Group related transcripts
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,                      -- Timestamp when AI processing completed
    metadata JSONB DEFAULT '{}'::JSONB,            -- Flexible metadata storage
    embedding VECTOR(1024),                        -- Vector embedding for semantic search
    tag_confidence REAL CHECK (tag_confidence >= 0 AND tag_confidence <= 1),
    embedding_model TEXT,                          -- Track which model generated embedding
    classification_model TEXT,                     -- Track which model classified tags

    -- Constraint: Processed transcripts must have both summary and embedding
    CONSTRAINT processed_complete CHECK (
        (processed_at IS NULL AND summary IS NULL AND embedding IS NULL) OR
        (processed_at IS NOT NULL AND summary IS NOT NULL AND embedding IS NOT NULL)
    )
);

-- Tags table: Hierarchical taxonomy for classification
CREATE TABLE tags (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    category TEXT NOT NULL,                        -- Top-level grouping (infra, study, backup, etc.)
    parent_tag_id INTEGER REFERENCES tags(id) ON DELETE SET NULL,
    obsidian_folder TEXT,                          -- Map to Obsidian vault folder structure
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Junction table: Many-to-many relationship with confidence scores
CREATE TABLE transcript_tags (
    transcript_id UUID REFERENCES transcripts(id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    assigned_by TEXT NOT NULL,                     -- 'ai_model_name' or 'manual'
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (transcript_id, tag_id)
);

-- Comments for documentation
COMMENT ON TABLE transcripts IS 'Core storage for AI-processed transcripts with vector embeddings';
COMMENT ON COLUMN transcripts.embedding IS 'Vector(1024) for semantic similarity search using pgvector';
COMMENT ON COLUMN transcripts.metadata IS 'JSONB field for flexible attributes: speaker count, duration, language, etc.';
COMMENT ON TABLE tags IS 'Hierarchical taxonomy supporting parent-child relationships';
COMMENT ON TABLE transcript_tags IS 'Junction table with AI confidence scores for multi-label classification';
