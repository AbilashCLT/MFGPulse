-- ============================================================================
-- MFGPulse AI: 13 Cortex Search Service
-- RAG over maintenance logs for root cause investigation
-- ============================================================================

USE DATABASE MFGPULSE_DB;

CREATE OR REPLACE CORTEX SEARCH SERVICE ML_MODELS.MAINTENANCE_SEARCH
    ON search_text
    ATTRIBUTES asset_id, wo_type
    WAREHOUSE = COMPUTE_WH
    TARGET_LAG = '1 day'
    AS (
        SELECT
            ml.LOG_ID AS doc_id,
            ml.ASSET_ID,
            wo.WO_TYPE,
            CONCAT(
                'Asset: ', am.ASSET_NAME, ' (', ml.ASSET_ID, '). ',
                'Work order: ', ml.WO_ID, ' [', wo.WO_TYPE, ', ', wo.PRIORITY, ']. ',
                'Date: ', ml.TIMESTAMP::VARCHAR, '. ',
                'Technician: ', ml.TECHNICIAN, '. ',
                'Notes: ', ml.NOTES_TEXT
            ) AS search_text
        FROM RAW_IT.MAINTENANCE_LOGS ml
        JOIN RAW_OT.ASSET_MASTER am ON ml.ASSET_ID = am.ASSET_ID
        LEFT JOIN RAW_IT.WORK_ORDERS wo ON ml.WO_ID = wo.WO_ID
    );
