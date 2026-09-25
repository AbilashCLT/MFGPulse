-- ============================================================
-- MFGPulse AI — Bulk Operations End-to-End Test
-- ============================================================
-- Run this AFTER executing sql/21_bulk_audit_log.sql
-- Tests all 6 bulk operation paths against live data.
-- ============================================================

USE DATABASE MFGPULSE_DB;
USE SCHEMA ANALYTICS;

-- ============================================================
-- PRE-TEST: Snapshot current state
-- ============================================================
SELECT 'PRE-TEST WO STATUS' AS SECTION, STATUS, COUNT(*) AS CNT
FROM RAW_IT.WORK_ORDERS GROUP BY STATUS ORDER BY STATUS;

SELECT 'PRE-TEST PO STATUS' AS SECTION, STATUS, COUNT(*) AS CNT
FROM RAW_IT.PURCHASE_ORDERS GROUP BY STATUS ORDER BY STATUS;

-- ============================================================
-- TEST 1: Bulk Start WOs (open → in_progress)
-- ============================================================
-- Pick 2 open WOs
SET test_wo_1 = (SELECT WO_ID FROM RAW_IT.WORK_ORDERS WHERE STATUS = 'open' LIMIT 1);
SET test_wo_2 = (SELECT WO_ID FROM RAW_IT.WORK_ORDERS WHERE STATUS = 'open' AND WO_ID != $test_wo_1 LIMIT 1);

-- Start them
UPDATE RAW_IT.WORK_ORDERS SET STATUS = 'in_progress' WHERE WO_ID = $test_wo_1;
UPDATE RAW_IT.WORK_ORDERS SET STATUS = 'in_progress' WHERE WO_ID = $test_wo_2;

-- Log the bulk operation
CALL MFGPULSE_DB.ANALYTICS.LOG_BULK_OPERATION(
    'BULK_START', 'WO',
    ARRAY_CONSTRUCT($test_wo_1, $test_wo_2),
    2, 2, 0, NULL, 'TEST_USER', 'SHIFT_SUPERVISOR',
    PARSE_JSON('null')
);

-- Verify
SELECT 'TEST 1: Bulk Start' AS TEST, STATUS, WO_ID
FROM RAW_IT.WORK_ORDERS
WHERE WO_ID IN ($test_wo_1, $test_wo_2);

-- ============================================================
-- TEST 2: Bulk Complete WOs (in_progress → completed)
-- ============================================================
SET test_wo_3 = (SELECT WO_ID FROM RAW_IT.WORK_ORDERS WHERE STATUS = 'in_progress' LIMIT 1);
SET test_wo_4 = (SELECT WO_ID FROM RAW_IT.WORK_ORDERS WHERE STATUS = 'in_progress' AND WO_ID != $test_wo_3 LIMIT 1);

UPDATE RAW_IT.WORK_ORDERS
SET STATUS = 'completed', COMPLETED_DATE = CURRENT_TIMESTAMP(),
    ROOT_CAUSE_CONFIRMED = 'bearing_wear', PART_USED = TRUE
WHERE WO_ID IN ($test_wo_3, $test_wo_4);

-- Release any active reservations
UPDATE RAW_IT.PART_RESERVATIONS SET STATUS = 'consumed'
WHERE WO_ID IN ($test_wo_3, $test_wo_4) AND STATUS = 'active';

-- Log the bulk operation
CALL MFGPULSE_DB.ANALYTICS.LOG_BULK_OPERATION(
    'BULK_COMPLETE', 'WO',
    ARRAY_CONSTRUCT($test_wo_3, $test_wo_4),
    2, 2, 0, NULL, 'TEST_USER', 'SHIFT_SUPERVISOR',
    PARSE_JSON('{"root_cause": "bearing_wear", "part_used": true}')
);

-- Verify
SELECT 'TEST 2: Bulk Complete' AS TEST, STATUS, ROOT_CAUSE_CONFIRMED, PART_USED, WO_ID
FROM RAW_IT.WORK_ORDERS
WHERE WO_ID IN ($test_wo_3, $test_wo_4);

-- ============================================================
-- TEST 3: Bulk Approve POs (pending_approval → approved)
-- ============================================================
SET test_po_1 = (SELECT PO_ID FROM RAW_IT.PURCHASE_ORDERS WHERE STATUS = 'pending_approval' LIMIT 1);
SET test_po_2 = (SELECT PO_ID FROM RAW_IT.PURCHASE_ORDERS WHERE STATUS = 'pending_approval' AND PO_ID != $test_po_1 LIMIT 1);
SET test_po_3 = (SELECT PO_ID FROM RAW_IT.PURCHASE_ORDERS WHERE STATUS = 'pending_approval' AND PO_ID NOT IN ($test_po_1, $test_po_2) LIMIT 1);

UPDATE RAW_IT.PURCHASE_ORDERS SET STATUS = 'approved'
WHERE PO_ID IN ($test_po_1, $test_po_2, $test_po_3);

CALL MFGPULSE_DB.ANALYTICS.LOG_BULK_OPERATION(
    'BULK_APPROVE', 'PO',
    ARRAY_CONSTRUCT($test_po_1, $test_po_2, $test_po_3),
    3, 3, 0, NULL, 'TEST_USER', 'PROCUREMENT_ADMIN',
    PARSE_JSON('null')
);

-- Verify
SELECT 'TEST 3: Bulk Approve' AS TEST, STATUS, PO_ID
FROM RAW_IT.PURCHASE_ORDERS
WHERE PO_ID IN ($test_po_1, $test_po_2, $test_po_3);

-- ============================================================
-- TEST 4: Bulk Reject POs (pending_approval → cancelled)
-- ============================================================
SET test_po_4 = (SELECT PO_ID FROM RAW_IT.PURCHASE_ORDERS WHERE STATUS = 'pending_approval' LIMIT 1);
SET test_po_5 = (SELECT PO_ID FROM RAW_IT.PURCHASE_ORDERS WHERE STATUS = 'pending_approval' AND PO_ID != $test_po_4 LIMIT 1);

UPDATE RAW_IT.PURCHASE_ORDERS
SET STATUS = 'cancelled',
    REJECTION_REASON = 'Bulk test: budget exceeded',
    REJECTED_BY = 'TEST_USER',
    REJECTED_AT = CURRENT_TIMESTAMP()
WHERE PO_ID IN ($test_po_4, $test_po_5);

CALL MFGPULSE_DB.ANALYTICS.LOG_BULK_OPERATION(
    'BULK_REJECT', 'PO',
    ARRAY_CONSTRUCT($test_po_4, $test_po_5),
    2, 2, 0, NULL, 'TEST_USER', 'PROCUREMENT_ADMIN',
    PARSE_JSON('{"rejection_reason": "Bulk test: budget exceeded"}')
);

-- Verify
SELECT 'TEST 4: Bulk Reject' AS TEST, STATUS, REJECTION_REASON, REJECTED_BY, PO_ID
FROM RAW_IT.PURCHASE_ORDERS
WHERE PO_ID IN ($test_po_4, $test_po_5);

-- ============================================================
-- TEST 5: Bulk Receive POs (approved → received)
-- ============================================================
SET test_po_6 = (SELECT PO_ID FROM RAW_IT.PURCHASE_ORDERS WHERE STATUS = 'approved' LIMIT 1);

UPDATE RAW_IT.PURCHASE_ORDERS SET STATUS = 'received'
WHERE PO_ID = $test_po_6;

CALL MFGPULSE_DB.ANALYTICS.LOG_BULK_OPERATION(
    'BULK_RECEIVE', 'PO',
    ARRAY_CONSTRUCT($test_po_6),
    1, 1, 0, NULL, 'TEST_USER', 'PROCUREMENT_ADMIN',
    PARSE_JSON('null')
);

-- Verify
SELECT 'TEST 5: Bulk Receive' AS TEST, STATUS, PO_ID
FROM RAW_IT.PURCHASE_ORDERS
WHERE PO_ID = $test_po_6;

-- ============================================================
-- VERIFY AUDIT LOG
-- ============================================================
SELECT 'AUDIT LOG' AS SECTION, LOG_ID, OPERATION_TYPE, ENTITY_TYPE,
    ENTITY_IDS, TOTAL_SELECTED, TOTAL_SUCCEEDED, TOTAL_BLOCKED,
    BLOCKED_REASON, PERFORMED_BY, PERSONA, DETAILS, CREATED_AT
FROM MFGPULSE_DB.ANALYTICS.BULK_OPERATION_LOG
ORDER BY LOG_ID;

-- ============================================================
-- POST-TEST: Final state
-- ============================================================
SELECT 'POST-TEST WO STATUS' AS SECTION, STATUS, COUNT(*) AS CNT
FROM RAW_IT.WORK_ORDERS GROUP BY STATUS ORDER BY STATUS;

SELECT 'POST-TEST PO STATUS' AS SECTION, STATUS, COUNT(*) AS CNT
FROM RAW_IT.PURCHASE_ORDERS GROUP BY STATUS ORDER BY STATUS;

-- ============================================================
-- ROLLBACK (optional — uncomment to revert test changes)
-- ============================================================
-- UPDATE RAW_IT.WORK_ORDERS SET STATUS = 'open' WHERE WO_ID IN ($test_wo_1, $test_wo_2);
-- UPDATE RAW_IT.WORK_ORDERS SET STATUS = 'in_progress', COMPLETED_DATE = NULL, ROOT_CAUSE_CONFIRMED = NULL, PART_USED = NULL WHERE WO_ID IN ($test_wo_3, $test_wo_4);
-- UPDATE RAW_IT.PURCHASE_ORDERS SET STATUS = 'pending_approval' WHERE PO_ID IN ($test_po_1, $test_po_2, $test_po_3);
-- UPDATE RAW_IT.PURCHASE_ORDERS SET STATUS = 'pending_approval', REJECTION_REASON = NULL, REJECTED_BY = NULL, REJECTED_AT = NULL WHERE PO_ID IN ($test_po_4, $test_po_5);
-- UPDATE RAW_IT.PURCHASE_ORDERS SET STATUS = 'approved' WHERE PO_ID = $test_po_6;
-- DELETE FROM MFGPULSE_DB.ANALYTICS.BULK_OPERATION_LOG WHERE PERFORMED_BY = 'TEST_USER';
