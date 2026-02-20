-- =====================================================
-- Add Documents Table for File Management
-- =====================================================

-- Create documents table
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('file', 'folder')),
    extension VARCHAR(50),
    parent_id UUID REFERENCES documents(id) ON DELETE CASCADE,
    file_url TEXT,
    file_size BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_documents_project_id ON documents(project_id);
CREATE INDEX IF NOT EXISTS idx_documents_parent_id ON documents(parent_id);
CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(type);

-- Row Level Security
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

-- RLS Policies for documents
CREATE POLICY "Users can manage documents for their projects"
    ON documents
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM projects
            WHERE projects.id = documents.project_id
            AND projects.user_id = auth.uid()
        )
    );

-- Trigger for updated_at
CREATE TRIGGER update_documents_updated_at
    BEFORE UPDATE ON documents
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
