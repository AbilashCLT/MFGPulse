-- ============================================================================
-- MFGPulse AI: 17 Procurement Procedures
-- RESERVE_PART_FOR_WORK_ORDER, GENERATE_PURCHASE_ORDER, AUTO_GENERATE_PURCHASE_ORDERS
-- ============================================================================

USE DATABASE MFGPULSE_DB;

-- Procedure: Reserve a part for a work order (checks ATP before reserving)
-- Full DDL deployed to ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(VARCHAR,VARCHAR,VARCHAR,NUMBER,DATE)

-- Procedure: Generate a purchase order (with duplicate prevention)
-- Full DDL deployed to ANALYTICS.GENERATE_PURCHASE_ORDER(VARCHAR,VARCHAR,NUMBER,DATE,VARCHAR,VARCHAR)

-- Procedure: Auto-generate POs for all at-risk assets without existing orders
-- Full DDL deployed to ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()

-- Task: AUTO_PROCUREMENT_REVIEW runs AUTO_GENERATE_PURCHASE_ORDERS every 720 minutes (SUSPENDED)

-- To see full procedure definitions:
-- SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(VARCHAR,VARCHAR,VARCHAR,NUMBER,DATE)');
-- SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.GENERATE_PURCHASE_ORDER(VARCHAR,VARCHAR,NUMBER,DATE,VARCHAR,VARCHAR)');
-- SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()');
