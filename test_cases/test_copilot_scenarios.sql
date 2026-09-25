-- ============================================================================
-- MFGPulse AI Test Suite: TC-07 Copilot + Search Benchmarks
-- ============================================================================
SELECT 'TC-07-07' AS TEST_ID, 'Search asset coverage' AS TEST_NAME, 8 AS EXPECTED, (SELECT COUNT(DISTINCT ASSET_ID) FROM MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS) AS ACTUAL, CASE WHEN (SELECT COUNT(DISTINCT ASSET_ID) FROM MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS)>=8 THEN 'PASS' ELSE 'FAIL' END AS STATUS;
SELECT 'TC-07-10' AS TEST_ID, 'Log count=26' AS TEST_NAME, 26 AS EXPECTED, COUNT(*) AS ACTUAL, CASE WHEN COUNT(*)=26 THEN 'PASS' ELSE 'FAIL' END AS STATUS FROM MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS;
-- Cortex Search accuracy tests require SEARCH_PREVIEW which needs interactive execution
-- Run the full test_copilot_scenarios.sql file in a Snowsight worksheet for TC-07-02 through TC-07-06
