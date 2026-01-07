-- ============================================
-- INITIAL SETUP
-- ============================================
-- This script creates the database, schema, role, and grants
-- needed for the document processing demo.
--
-- Uses SET variables for parameterization.
-- EXECUTE IMMEDIATE is used for GRANT statements (no output).
-- Verification queries show results.
--
-- PREREQUISITES: Run as ACCOUNTADMIN or a role with sufficient privileges
-- ============================================

-- ============================================
-- CONFIGURATION PARAMETERS - Set these values
-- ============================================
SET database_name = 'doc_processing_walkthrough';
SET schema_name = 'poc';
SET role_name = 'doc_processing_walkthrough_role';
SET stage_name = 'FILESTAGE';
SET warehouse_name = 'compute_wh';
SET user_name = '';


-- ============================================
-- SETUP SCRIPT - Uses parameters from above
-- ============================================
-- Use ACCOUNTADMIN, SYSADMIN, SECURITYADMIN, etc. based on your RBAC setup
-- Using ACCOUNTADMIN here for simplicity
USE ROLE ACCOUNTADMIN;

-- Create database and schema (output visible!)
CREATE OR REPLACE DATABASE IDENTIFIER($database_name);
CREATE OR REPLACE SCHEMA IDENTIFIER($schema_name);

-- Create a stage for uploading documents (output visible!)
CREATE OR REPLACE STAGE IDENTIFIER($stage_name)
ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
DIRECTORY = (ENABLE = TRUE)
COMMENT = 'Stage for document processing with AI functions';

-- Create the role (output visible!)
CREATE ROLE IF NOT EXISTS IDENTIFIER($role_name);

-- Grant statements using Snowflake Scripting block
-- (GRANTs don't support IDENTIFIER, so we use dynamic SQL)
DECLARE
    db_name VARCHAR := $database_name;
    sch_name VARCHAR := $schema_name;
    rl_name VARCHAR := $role_name;
    wh_name VARCHAR := $warehouse_name;
    usr_name VARCHAR := $user_name;
BEGIN
    -- Grant role to user
    EXECUTE IMMEDIATE 'GRANT ROLE ' || rl_name || ' TO USER ' || usr_name;
    
    -- Database and schema grants
    EXECUTE IMMEDIATE 'GRANT USAGE ON DATABASE ' || db_name || ' TO ROLE ' || rl_name;
    EXECUTE IMMEDIATE 'GRANT USAGE, CREATE TABLE, CREATE STAGE, CREATE CORTEX SEARCH SERVICE ON ALL SCHEMAS IN DATABASE ' || db_name || ' TO ROLE ' || rl_name;
    EXECUTE IMMEDIATE 'GRANT READ ON ALL STAGES IN DATABASE ' || db_name || ' TO ROLE ' || rl_name;
    
    -- Warehouse grants
    EXECUTE IMMEDIATE 'GRANT USAGE, OPERATE ON WAREHOUSE ' || wh_name || ' TO ROLE ' || rl_name;
    
    -- Cortex AI grants (required for AI_PARSE_DOCUMENT, embeddings, search, agents)
    EXECUTE IMMEDIATE 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ' || rl_name;
    EXECUTE IMMEDIATE 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_EMBED_USER TO ROLE ' || rl_name;
    EXECUTE IMMEDIATE 'GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ' || rl_name;
    EXECUTE IMMEDIATE 'GRANT CREATE AGENT ON SCHEMA ' || db_name || '.' || sch_name || ' TO ROLE ' || rl_name;
    
    RETURN 'Grants completed for role: ' || rl_name;
END;

-- Verify grants (output visible!)
SHOW GRANTS TO ROLE IDENTIFIER($role_name);


-- ============================================
-- SWITCH TO THE NEW ROLE
-- ============================================
USE ROLE IDENTIFIER($role_name);
USE SECONDARY ROLES NONE;
USE WAREHOUSE IDENTIFIER($warehouse_name);
USE DATABASE IDENTIFIER($database_name);
USE SCHEMA IDENTIFIER($schema_name);

-- Verify context (output visible!)
SELECT CURRENT_ROLE() as role, CURRENT_DATABASE() as database, 
       CURRENT_SCHEMA() as schema, CURRENT_WAREHOUSE() as warehouse;
