-- ============================================
-- CORTEX SEARCH SETUP
-- ============================================
-- This script demonstrates how to:
--   1. Parse PDF documents using AI_PARSE_DOCUMENT
--   2. Chunk the extracted text for better retrieval
--   3. Create a Cortex Search Service for semantic search
--
-- PREREQUISITES:
--   1. Run 01_setup.sql first to create the database, schema, stage, and role
--   2. Upload your PDF documents to the stage:
--      PUT file:///path/to/your/documents/*.pdf @database.schema.FILESTAGE;
--
-- HOW TO RUN:
--   Run each section separately (select the statements and run).
--   Do NOT use "Run All" - the anonymous blocks need to be run individually.
-- ============================================

-- ============================================
-- CONFIGURATION PARAMETERS - Set these values
-- (Should match the values used in 01_setup.sql)
-- ============================================
SET database_name = 'doc_processing_walkthrough';
SET schema_name = 'poc';
SET role_name = 'doc_processing_walkthrough_role';
SET warehouse_name = 'compute_wh';
SET stage_name = 'FILESTAGE';

-- Table names (will be created in the database/schema above)
SET raw_text_table = 'RAW_TEXT';
SET chunks_table = 'DOCS_CHUNKS_TABLE';
SET search_service_name = 'DEMO_CORTEX_SEARCH_SERVICE';

-- Optional: specific file to test with (set to empty string '' to skip)
-- Upload files to the stage first, then set this to test a single file
SET test_file_name = '';


-- ============================================
-- SET EXECUTION CONTEXT
-- Run this section first!
-- ============================================
USE ROLE IDENTIFIER($role_name);
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA IDENTIFIER($schema_name);

-- Verify context (output visible)
SELECT CURRENT_ROLE() as role, CURRENT_DATABASE() as database, 
       CURRENT_SCHEMA() as schema, CURRENT_WAREHOUSE() as warehouse;


-- ============================================
-- STEP 1: EXPLORE AI_PARSE_DOCUMENT (Optional)
-- ============================================
-- AI_PARSE_DOCUMENT extracts text and structure from documents (PDFs, images, etc.)
-- Parameters:
--   - TO_FILE(): References a file in a stage
--   - 'mode': 'LAYOUT' preserves document structure (headers, paragraphs, tables)
--             'OCR' for scanned documents/images
--   - 'page_split': true returns content split by page
-- Returns JSON with extracted content, metadata, and structure

-- Test parsing a single file (uses dynamic SQL for stage reference)
-- Run this block by itself:
DECLARE
    stage_path VARCHAR := $database_name || '.' || $schema_name || '.' || $stage_name;
    test_file VARCHAR := $test_file_name;
BEGIN
    IF (test_file IS NOT NULL AND test_file != '') THEN
        EXECUTE IMMEDIATE '
            SELECT AI_PARSE_DOCUMENT(
                TO_FILE(''@' || stage_path || ''', ''' || test_file || '''), 
                { ''mode'': ''LAYOUT'', ''page_split'': true }
            ) AS parsed_document';
    END IF;
    RETURN 'Test parse complete (skipped if no test_file_name set)';
END;

-- View all files available in the stage
-- Run this block by itself:
DECLARE
    stage_path VARCHAR := $database_name || '.' || $schema_name || '.' || $stage_name;
BEGIN
    EXECUTE IMMEDIATE 'LIST @' || stage_path;
    RETURN 'LIST complete for stage: ' || stage_path;
END;


-- ============================================
-- STEP 2: PARSE ALL DOCUMENTS INTO RAW TEXT
-- ============================================
-- This creates a table with the full extracted text from each PDF
-- We use DIRECTORY() to iterate over all files in the stage

-- First, refresh the stage directory metadata
-- (Required after uploading files, otherwise DIRECTORY() won't see them)
ALTER STAGE IDENTIFIER($stage_name) REFRESH;

-- Parse all documents - Run this block by itself:
DECLARE
    db_name VARCHAR := $database_name;
    sch_name VARCHAR := $schema_name;
    stg_name VARCHAR := $stage_name;
    raw_tbl VARCHAR := $raw_text_table;
    stage_path VARCHAR;
    full_table_name VARCHAR;
BEGIN
    stage_path := db_name || '.' || sch_name || '.' || stg_name;
    full_table_name := db_name || '.' || sch_name || '.' || raw_tbl;
    
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE TABLE ' || full_table_name || ' AS
        WITH FILE_TABLE as (
          SELECT 
                RELATIVE_PATH,
                SIZE,
                FILE_URL,
                build_scoped_file_url(@' || stage_path || ', relative_path) as scoped_file_url,
                TO_FILE(''@' || stage_path || ''', RELATIVE_PATH) AS docs 
            FROM 
                DIRECTORY(@' || stage_path || ')
        )
        SELECT 
            RELATIVE_PATH,
            SIZE,
            FILE_URL,
            scoped_file_url,
            TO_VARCHAR (
                SNOWFLAKE.CORTEX.AI_PARSE_DOCUMENT (
                    docs,
                    {''mode'': ''LAYOUT''} ):content
                ) AS EXTRACTED_LAYOUT 
        FROM 
            FILE_TABLE';
    
    RETURN 'Created table: ' || full_table_name || ' from stage: ' || stage_path;
END;

-- Preview the results (output visible!)
SELECT * FROM IDENTIFIER($raw_text_table) LIMIT 5;


-- ============================================
-- STEP 3: CHUNK THE DOCUMENTS
-- ============================================
-- Large documents need to be split into smaller chunks for effective retrieval.
-- Chunking strategy matters for RAG (Retrieval-Augmented Generation):
--   - Too large: loses specificity, may exceed context limits
--   - Too small: loses context, fragments meaning
-- 
-- We use SPLIT_TEXT_RECURSIVE_CHARACTER which intelligently splits on
-- natural boundaries (paragraphs, sentences) rather than arbitrary positions.

-- Create the chunks table (output visible!)
CREATE OR REPLACE TABLE IDENTIFIER($chunks_table) ( 
    RELATIVE_PATH VARCHAR(16777216),      -- Source filename
    SIZE NUMBER(38,0),                    -- Original file size
    FILE_URL VARCHAR(16777216),           -- Permanent file URL
    SCOPED_FILE_URL VARCHAR(16777216),    -- Temporary secure URL
    CHUNK VARCHAR(16777216),              -- The actual text chunk
    CHUNK_INDEX INTEGER,                  -- Position of chunk within document (0-based)
    CATEGORY VARCHAR(16777216)            -- Optional: for filtering search results
);

-- Populate the chunks table - Run this block by itself:
DECLARE
    chunks_tbl VARCHAR := $chunks_table;
    raw_tbl VARCHAR := $raw_text_table;
BEGIN
    EXECUTE IMMEDIATE '
        INSERT INTO ' || chunks_tbl || ' (relative_path, size, file_url,
                                scoped_file_url, chunk, chunk_index)
        SELECT relative_path, 
                size,
                file_url, 
                scoped_file_url,
                c.value::TEXT as chunk,
                c.INDEX::INTEGER as chunk_index
        FROM 
            ' || raw_tbl || ',
            LATERAL FLATTEN( input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER (
                  EXTRACTED_LAYOUT,
                  ''markdown'',
                  1512,
                  256,
                  [''\n\n'', ''\n'', '' '', '''']
               )) c';
    
    RETURN 'Inserted chunks into: ' || chunks_tbl;
END;

-- Preview the chunks (output visible!)
SELECT * FROM IDENTIFIER($chunks_table) LIMIT 10;

-- Check chunk statistics per document (output visible!)
SELECT 
    relative_path,
    COUNT(*) as num_chunks,
    AVG(LENGTH(chunk)) as avg_chunk_length
FROM IDENTIFIER($chunks_table)
GROUP BY relative_path;


-- ============================================
-- STEP 4: CREATE CORTEX SEARCH SERVICE
-- ============================================
-- Cortex Search provides semantic/hybrid search over your data.
-- It automatically:
--   - Generates embeddings for your text chunks
--   - Creates and maintains a vector index
--   - Handles keyword + semantic hybrid search
--   - Stays in sync with source data (within TARGET_LAG)
--
-- The search service can be queried via SQL or used with Cortex Agents

-- Create the search service - Run this block by itself:
DECLARE
    search_svc VARCHAR := $search_service_name;
    wh_name VARCHAR := $warehouse_name;
    chunks_tbl VARCHAR := $chunks_table;
BEGIN
    EXECUTE IMMEDIATE '
        CREATE OR REPLACE CORTEX SEARCH SERVICE ' || search_svc || '
        ON chunk
        WAREHOUSE = ' || wh_name || '
        TARGET_LAG = ''1 day''
        AS (
            SELECT chunk,
                chunk_index,
                relative_path,
                file_url,
                category
            FROM ' || chunks_tbl || '
        )';
    
    RETURN 'Created search service: ' || search_svc;
END;

-- Verify the search service was created (output visible!)
SHOW CORTEX SEARCH SERVICES;


-- ============================================
-- STEP 5: TEST THE SEARCH SERVICE
-- ============================================
-- Query the search service to verify it's working
-- Note: The search service may take a few minutes to become ready after creation

-- Simple test query (run this directly - no dynamic SQL needed)
-- Replace 'DEMO_CORTEX_SEARCH_SERVICE' if you changed search_service_name
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'DEMO_CORTEX_SEARCH_SERVICE',
        '{
            "query": "What are the key findings?",
            "columns": ["chunk", "relative_path"],
            "limit": 3
        }'
    )
)['results'] as search_results;


-- ============================================
-- NEXT STEPS
-- ============================================
-- Now you can:
--   1. Query the search service directly with SEARCH_PREVIEW()
--   2. Create a Cortex Agent that uses this search service for RAG
--   3. Build applications that leverage semantic document search
