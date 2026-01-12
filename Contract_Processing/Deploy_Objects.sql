-- Update these values to your environment 
Use database doc_processing_walkthrough;
use schema poc;
use role doc_processing_walkthrough_role;
use warehouse compute_wh;

-- First, let's take a look at what files we're working with
-- Update this to point to your stagea and directory 
list @filestage/contracts;

-- Let's take a look at one of the files
-- There are two modes of document parsing: OCR and Layout. 
--      Use OCR as the default, and Layout to support documents with a lot of structural content like tables
--      See the differences here: https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document
SELECT AI_PARSE_DOCUMENT(
        TO_FILE('@filestage/contracts/BEAM_EX-1.1.pdf'),   -- update this to point to one of your own files
        {'mode': 'OCR' , 'page_split': true})
AS parsed_document; 

-- We simply want to store the output above into a table, and include all the other files we're interested in
-- Additionally, during this step, I'm going to use some other AI features to help classify the documents
-- This part is not required, but can be beneficial if some light logic can provide attributes around the documents
-- We can classify documents with AI_CLASSIFY, translate with AI_TRANSLATE, etc. see functions here --> https://docs.snowflake.com/en/sql-reference/functions/ai_complete
CREATE OR REPLACE TABLE contract_raw_text AS
SELECT
    RELATIVE_PATH,
    AI_EXTRACT(
      file => TO_FILE('@filestage', relative_path),
      responseFormat => [
        'What is the effective date of this document?',
        'What is the name of the organization in this document who should be referred to as the company?',
        'What is the aggregate offering price?'
      ]
    ) as extracted_fields,
    TO_VARCHAR (
        SNOWFLAKE.CORTEX.PARSE_DOCUMENT (
            '@filestage',
            RELATIVE_PATH,
            {'mode': 'LAYOUT'} ):content
        ) AS EXTRACTED_LAYOUT
FROM
    DIRECTORY('@filestage')
WHERE
    RELATIVE_PATH LIKE '%.pdf'
    and RELATIVE_PATH LIKE 'contracts/%';


SELECT * FROM CONTRACT_RAW_TEXT;


-- now let's just chunk this information for optimal LLM usage
CREATE OR REPLACE TABLE contract_document_chunks AS
SELECT
    relative_path,
    TO_DATE(extracted_fields:response:"What is the effective date of this document?"::string, 'MMMM DD, YYYY') as effective_date,
    extracted_fields:response:"What is the name of the organization in this document who should be referred to as the company?"::varchar as company_name,
    BUILD_SCOPED_FILE_URL(@filestage, relative_path) AS file_url,
    (
        relative_path || ':\n'
        || coalesce('Header 1: ' || c.value['headers']['header_1'] || '\n', '')
        || coalesce('Header 2: ' || c.value['headers']['header_2'] || '\n', '')
        || c.value['chunk']
    ) AS chunk,
    'English' AS language
FROM
    contract_raw_text,
    LATERAL FLATTEN(SNOWFLAKE.CORTEX.SPLIT_TEXT_MARKDOWN_HEADER(
        EXTRACTED_LAYOUT,
        OBJECT_CONSTRUCT('#', 'header_1', '##', 'header_2'),
        2000, -- chunks of 2000 characters
        300 -- 300 character overlap
    )) c;


select * from contract_document_chunks;


-- Now, let's create a search service! 
CREATE OR REPLACE CORTEX SEARCH SERVICE contract_search_service
    ON chunk
    ATTRIBUTES company_name, effective_date
    WAREHOUSE = compute_wh
    TARGET_LAG = '1 day'
    AS (
    SELECT
        chunk,
        relative_path,
        file_url,
        company_name,
        effective_date
    FROM contract_document_chunks
    );

-- Searching across the documents for lexical & semantic search, plus reranking
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'contract_search_service',
        '{
            "query": "What state laws are called out?",
            "columns": ["chunk", "relative_path"],
            "limit": 3
        }'
    )
)['results'] as search_results;

