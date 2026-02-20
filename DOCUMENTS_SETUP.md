# Documents Feature - Database Integration Setup

## Overview
The Documents page has been integrated with Supabase to store both document metadata and files.

## Database Setup

### 1. Run the Migration
Execute the migration file to create the documents table:
```sql
-- File: migration_add_documents_table.sql
```

You can run this migration in your Supabase SQL Editor:
1. Go to your Supabase Dashboard
2. Navigate to SQL Editor
3. Copy and paste the contents of `migration_add_documents_table.sql`
4. Click "Run"

### 2. Create Storage Bucket
Create a storage bucket for documents:
1. Go to Supabase Dashboard → Storage
2. Create a new bucket named `documents`
3. Set it to **Public** if you want files to be accessible via URL
4. Configure RLS policies if needed

### Storage Bucket Policies (Optional)
If you want more control, add these policies to the `documents` bucket:

**Allow authenticated users to upload:**
```sql
CREATE POLICY "Users can upload documents"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'documents' AND
  (storage.foldername(name))[1] IN (
    SELECT id::text FROM projects WHERE user_id = auth.uid()
  )
);
```

**Allow authenticated users to view their project documents:**
```sql
CREATE POLICY "Users can view their documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents' AND
  (storage.foldername(name))[1] IN (
    SELECT id::text FROM projects WHERE user_id = auth.uid()
  )
);
```

**Allow authenticated users to delete their documents:**
```sql
CREATE POLICY "Users can delete their documents"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'documents' AND
  (storage.foldername(name))[1] IN (
    SELECT id::text FROM projects WHERE user_id = auth.uid()
  )
);
```

## Features Implemented

### 1. **Folder Management**
- ✅ Create folders (saved to database)
- ✅ Rename folders (updates database)
- ✅ Delete folders (removes from database and all child documents)
- ✅ Auto-rename on creation
- ✅ Navigate into folders

### 2. **File Upload**
- ✅ Upload multiple files at once
- ✅ Save files to Supabase Storage (`documents` bucket)
- ✅ Save file metadata to database (name, type, extension, size, URL)
- ✅ Support for multiple file types (CSV, DOC, DOCX, XLS, XLSX, HEIC, JPG, JPEG, PNG, WEBP, MP4, PDF, DWG, ZIP, TXT, DXF)
- ✅ Generate and store public URLs for file access

### 3. **File Management**
- ✅ Rename files (updates database)
- ✅ Delete files (removes from storage and database)
- ✅ Double-click to open files in new tab
- ✅ Display file metadata (uploaded/updated date)

### 4. **Database Schema**
The `documents` table includes:
- `id` - UUID primary key
- `project_id` - References projects table
- `name` - Document/folder name
- `type` - 'file' or 'folder'
- `extension` - File extension (for files only)
- `parent_id` - UUID for nested folders
- `file_url` - Public URL from Supabase Storage
- `file_size` - File size in bytes
- `created_at` - Timestamp
- `updated_at` - Timestamp (auto-updated)

## File Storage Structure
Files are stored in Supabase Storage with this path structure:
```
documents/
  └── {project_id}/
      ├── root/
      │   └── {timestamp}-{filename}
      └── {folder_id}/
          └── {timestamp}-{filename}
```

## How It Works

1. **Loading Documents**: When the page loads, it fetches all documents for the current project from Supabase
2. **Creating Folders**: Creates a database record with type='folder'
3. **Uploading Files**: 
   - Uploads file binary to Supabase Storage
   - Gets the public URL
   - Saves metadata to database with the URL
4. **Renaming**: Updates the `name` field in the database
5. **Deleting**:
   - For files: Removes from storage then database
   - For folders: Cascading delete removes all children
6. **Opening Files**: Uses the stored `file_url` to open in a new tab

## Testing

To test the integration:
1. Make sure your Supabase project is properly configured
2. Run the migration to create the `documents` table
3. Create the `documents` storage bucket
4. Open a project in the app
5. Try uploading files and creating folders
6. Check Supabase Dashboard:
   - Table Editor → documents (should see records)
   - Storage → documents (should see uploaded files)

## Notes
- Files are automatically deleted from storage when deleted from the UI
- Folders cascade delete all their contents
- The `parent_id` allows for nested folder structures
- Row Level Security ensures users can only access their project's documents
