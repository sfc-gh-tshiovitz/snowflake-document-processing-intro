# Snowflake Document Processing Introduction

A hands-on introduction to processing documents with Snowflake Cortex AI functions. This project demonstrates how to:

- Parse PDFs and extract text using `AI_PARSE_DOCUMENT`
- Chunk documents for effective retrieval
- Create a Cortex Search Service for semantic search
- Build the foundation for RAG (Retrieval-Augmented Generation) applications

## Prerequisites

- **Snowflake Account** with access to Cortex AI features
- **Snowsight** (Snowflake's web interface)
- **ACCOUNTADMIN** role (or equivalent) to run the initial setup
- Documents (PDFs) to process

### Required Cortex Privileges

Your role needs the following database roles granted:
- `SNOWFLAKE.CORTEX_USER` - For AI functions
- `SNOWFLAKE.CORTEX_EMBED_USER` - For embeddings
- `SNOWFLAKE.CORTEX_AGENT_USER` - For agents (optional)

The setup script grants these automatically to the created role.

## Quick Start

### 1. Run the Setup Script

Open `01_setup.sql` in a Snowsight worksheet and run all statements:

```sql
-- This creates:
-- • Database: doc_processing_walkthrough
-- • Schema: poc
-- • Stage: FILESTAGE (for uploading documents)
-- • Role: doc_processing_walkthrough_role (with all necessary grants)
```

### 2. Upload Documents to the Stage

**Option A: Using Snowsight UI**
1. Navigate to **Data** → **Databases** → `doc_processing_walkthrough` → `poc` → **Stages** → `FILESTAGE`
2. Click **+ Files** to upload your PDFs

**Option B: Using SQL (from SnowSQL or local client)**
```sql
PUT file:///path/to/your/documents/*.pdf @doc_processing_walkthrough.poc.FILESTAGE;
```

**Option C: Copy from an existing stage**
```sql
COPY FILES INTO @doc_processing_walkthrough.poc.FILESTAGE
FROM @existing_database.schema.stage;
```

### 3. Explore with Document Processing Playground (Optional)

Before running the automated pipeline, you can interactively explore your documents using Snowflake's **Document Processing Playground**.

#### Accessing the Playground

1. Sign in to **Snowsight**
2. In the navigation menu, select **AI & ML** → **Studio**
3. Find **Document Processing Playground** and click **Try**

#### Adding Documents from Your Stage

1. In the playground, click **Add from stage**
2. Select:
   - Database: `doc_processing_walkthrough`
   - Schema: `poc`
   - Stage: `FILESTAGE`
3. Choose up to 10 documents and click **Open playground**

#### Playground Features

| Tab | Description |
|-----|-------------|
| **Extraction** | Ask questions to extract information using `AI_EXTRACT` |
| **Markdown** | View the document layout (output of `AI_PARSE_DOCUMENT` in LAYOUT mode) |
| **Text** | View OCR text content |

#### Example Extractions

Create key-question pairs to extract structured data:

| Key | Question |
|-----|----------|
| `company_name` | What is the name of the company? |
| `date` | What is the date of this document? |
| `total_amount` | What is the total amount? |
| `summary` | Provide a brief summary of this document |

#### Generating Code Snippets

1. After exploring in the playground, click **Code Snippets** (top-right)
2. Select **Open in Worksheet** to get SQL you can use in your workflows

### 4. Run the Cortex Search Setup

Open `02_cortex_search_setup.sql` in a Snowsight worksheet.

⚠️ **Important**: Run each section separately (select statements and run). Do NOT use "Run All" because the anonymous blocks (`DECLARE...END`) need to be executed individually.

This script:
1. Parses all documents in the stage
2. Chunks the text for better retrieval
3. Creates a Cortex Search Service for semantic search

## Configuration Parameters

Both scripts use parameterized values. Update these at the top of each file:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `database_name` | `doc_processing_walkthrough` | Target database |
| `schema_name` | `poc` | Target schema |
| `role_name` | `doc_processing_walkthrough_role` | Role to create/use |
| `warehouse_name` | `compute_wh` | Warehouse for compute |
| `stage_name` | `FILESTAGE` | Stage for documents |
| `user_name` | `<your user>` | User to grant role to (setup only) |

## Script Details

### 01_setup.sql

Creates the infrastructure needed for document processing:

- Creates database and schema
- Creates an internal stage with directory enabled
- Creates a dedicated role with all necessary privileges
- Grants Cortex AI database roles

**Run as**: ACCOUNTADMIN (or role with CREATE DATABASE/ROLE privileges)

### 02_cortex_search_setup.sql

Processes documents and creates a search service:

| Step | What it does | Output visible? |
|------|--------------|-----------------|
| Context setup | Sets role, warehouse, database, schema | ✅ Yes |
| Step 1 | Test AI_PARSE_DOCUMENT on single file (optional) | Via RETURN message |
| Step 2 | Parse all documents into RAW_TEXT table | ✅ Yes (SELECT preview) |
| Step 3 | Chunk documents into DOCS_CHUNKS_TABLE | ✅ Yes (SELECT preview) |
| Step 4 | Create Cortex Search Service | ✅ Yes (SHOW command) |
| Step 5 | Test the search service | ✅ Yes |

**Run as**: The role created in setup (e.g., `doc_processing_walkthrough_role`)

## Troubleshooting

### "No rows returned" when querying RAW_TEXT table

The stage directory needs to be refreshed after uploading files:

```sql
ALTER STAGE IDENTIFIER($stage_name) REFRESH;
```

This is included in the scripts but needs to be run after uploading new files.

### "Role does not exist" errors

Make sure you've run `01_setup.sql` first, and that the role was granted to your user.

### Search service not returning results

The Cortex Search Service may take a few minutes to build its index after creation. Wait a moment and try again.

## Next Steps

After completing this setup, you can:

1. **Query the search service** directly:
   ```sql
   SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
       'DEMO_CORTEX_SEARCH_SERVICE',
       '{"query": "your question here", "columns": ["chunk", "relative_path"], "limit": 5}'
   );
   ```

2. **Create a Cortex Agent** that uses the search service for RAG

3. **Build applications** using the Snowflake connector with semantic search capabilities

## Resources

- [AI_PARSE_DOCUMENT Documentation](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)
- [AI_EXTRACT Documentation](https://docs.snowflake.com/en/sql-reference/functions/ai_extract)
- [Cortex Search Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
- [Document Processing Playground](https://docs.snowflake.com/en/user-guide/snowflake-cortex/document-processing-playground)
- [Cortex LLM Privileges](https://docs.snowflake.com/en/user-guide/snowflake-cortex/llm-privileges)
