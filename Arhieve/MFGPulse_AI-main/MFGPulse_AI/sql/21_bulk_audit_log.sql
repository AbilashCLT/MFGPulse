-- ============================================================
-- MFGPulse AI — Bulk Operation Audit Log
-- ============================================================
-- Creates a table and procedure to track all bulk WO/PO
-- operations performed via the WO/PO Console.
-- ============================================================

USE DATABASE MFGPULSE_DB;
USE SCHEMA ANALYTICS;

-- 1. Audit log table
CREATE TABLE IF NOT EXISTS MFGPULSE_DB.ANALYTICS.BULK_OPERATION_LOG (
    LOG_ID           NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    OPERATION_TYPE   VARCHAR(50)   NOT NULL,   -- BULK_START, BULK_COMPLETE, BULK_APPROVE, BULK_REJECT, BULK_RECEIVE, BULK_ORDER, BULK_SHIP
    ENTITY_TYPE      VARCHAR(10)   NOT NULL,   -- WO or PO
    ENTITY_IDS       ARRAY         NOT NULL,   -- Array of WO_IDs or PO_IDs that were acted on
    TOTAL_SELECTED   NUMBER        NOT NULL,   -- How many the user selected
    TOTAL_SUCCEEDED  NUMBER        NOT NULL,   -- How many succeeded
    TOTAL_BLOCKED    NUMBER        NOT NULL,   -- How many were blocked/skipped
    BLOCKED_REASON   VARCHAR(500),             -- Why blocked items were skipped (e.g. "ATP=0, no open PO")
    PERFORMED_BY     VARCHAR(100)  NOT NULL,   -- Username who performed the action
    PERSONA          VARCHAR(50)   NOT NULL,   -- Persona at time of action
    DETAILS          VARIANT,                  -- Additional context (root_cause, rejection_reason, part_used, etc.)
    CREATED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (LOG_ID)
);

-- 2. Logging procedure (callable from Streamlit via conn.session().sql)
CREATE OR REPLACE PROCEDURE MFGPULSE_DB.ANALYTICS.LOG_BULK_OPERATION(
    P_OPERATION_TYPE VARCHAR,
    P_ENTITY_TYPE    VARCHAR,
    P_ENTITY_IDS     ARRAY,
    P_TOTAL_SELECTED NUMBER,
    P_TOTAL_SUCCEEDED NUMBER,
    P_TOTAL_BLOCKED  NUMBER,
    P_BLOCKED_REASON VARCHAR,
    P_PERFORMED_BY   VARCHAR,
    P_PERSONA        VARCHAR,
    P_DETAILS        VARIANT
)
RETURNS VARIANT
LANGUAGE SQL
AS
BEGIN
    INSERT INTO MFGPULSE_DB.ANALYTICS.BULK_OPERATION_LOG
        (OPERATION_TYPE, ENTITY_TYPE, ENTITY_IDS, TOTAL_SELECTED,
         TOTAL_SUCCEEDED, TOTAL_BLOCKED, BLOCKED_REASON,
         PERFORMED_BY, PERSONA, DETAILS)
    VALUES
        (:P_OPERATION_TYPE, :P_ENTITY_TYPE, :P_ENTITY_IDS, :P_TOTAL_SELECTED,
         :P_TOTAL_SUCCEEDED, :P_TOTAL_BLOCKED, :P_BLOCKED_REASON,
         :P_PERFORMED_BY, :P_PERSONA, :P_DETAILS);

    RETURN OBJECT_CONSTRUCT(
        'status', 'logged',
        'operation', :P_OPERATION_TYPE,
        'entity_type', :P_ENTITY_TYPE,
        'succeeded', :P_TOTAL_SUCCEEDED,
        'blocked', :P_TOTAL_BLOCKED
    );
END;

-- 3. Verification
SELECT 'BULK_OPERATION_LOG table created' AS STATUS;
DESCRIBE TABLE MFGPULSE_DB.ANALYTICS.BULK_OPERATION_LOG;
