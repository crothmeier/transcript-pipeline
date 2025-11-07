-- Production-grade indexes for AI Transcript Pipeline
-- Optimized for 128GB RAM system with vector similarity search

-- Vector similarity search using HNSW (Hierarchical Navigable Small World)
-- HNSW provides faster approximate nearest neighbor search than IVFFlat
-- Parameters: m=16 (connections per layer), ef_construction=64 (build quality)
CREATE INDEX IF NOT EXISTS idx_transcripts_embedding_hnsw
ON transcripts
USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- Full-text search index using GIN (Generalized Inverted Index)
-- Enables fast text search across all transcript content
CREATE INDEX IF NOT EXISTS idx_transcripts_fts
ON transcripts
USING GIN (to_tsvector('english', raw_content));

-- JSONB metadata search using GIN
-- Supports efficient queries on metadata fields (e.g., metadata @> '{"language": "en"}')
CREATE INDEX IF NOT EXISTS idx_transcripts_metadata
ON transcripts
USING GIN (metadata);

-- Time-series optimization using BRIN (Block Range Index)
-- BRIN is highly efficient for sequential data like timestamps
-- Minimal storage overhead, excellent for time-based queries
CREATE INDEX IF NOT EXISTS idx_transcripts_created_at_brin
ON transcripts
USING BRIN (created_at)
WITH (pages_per_range = 128);

-- Standard B-tree indexes for common queries
CREATE INDEX IF NOT EXISTS idx_transcripts_conversation_id
ON transcripts (conversation_id)
WHERE conversation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transcripts_processed_at
ON transcripts (processed_at)
WHERE processed_at IS NOT NULL;

-- Tags category lookup optimization
CREATE INDEX IF NOT EXISTS idx_tags_category_name
ON tags (category, name);

-- Tag hierarchy traversal
CREATE INDEX IF NOT EXISTS idx_tags_parent
ON tags (parent_tag_id)
WHERE parent_tag_id IS NOT NULL;

-- Junction table indexes for efficient joins
CREATE INDEX IF NOT EXISTS idx_transcript_tags_tag_id
ON transcript_tags (tag_id);

CREATE INDEX IF NOT EXISTS idx_transcript_tags_confidence
ON transcript_tags (confidence DESC)
WHERE confidence >= 0.7;

-- Composite index for filtering by tag and confidence
CREATE INDEX IF NOT EXISTS idx_transcript_tags_tag_confidence
ON transcript_tags (tag_id, confidence DESC);

-- Analyze tables for query planner optimization
ANALYZE transcripts;
ANALYZE tags;
ANALYZE transcript_tags;

-- Comments for documentation
COMMENT ON INDEX idx_transcripts_embedding_hnsw IS 'HNSW vector index for sub-millisecond semantic similarity search';
COMMENT ON INDEX idx_transcripts_fts IS 'Full-text search index using PostgreSQL tsvector';
COMMENT ON INDEX idx_transcripts_created_at_brin IS 'BRIN index optimized for time-series queries with minimal storage';
