/*==========================================================================
  MFGPULSE_DB — Cross-Account Share & Replication Setup
  Account : ZB12211 (AWS_US_EAST_2)
  Org     : QEIPXIJ
  Role    : ACCOUNTADMIN
  
  This script:
    1. Creates an outbound share for the entire MFGPULSE_DB database
    2. Grants all schemas and tables to the share
    3. Enables database replication to target account(s)
    4. Creates a replication group bundling the database + share
    5. Verifies the setup from the provider side
  
  ACTION REQUIRED: Replace MRREAYA-HJ25985 with the fully-qualified
  target account name (e.g. QEIPXIJ.MY_OTHER_ACCOUNT).
==========================================================================*/

USE ROLE ACCOUNTADMIN;

--------------------------------------------------------------------------
-- 1. CREATE THE SHARE
--------------------------------------------------------------------------
CREATE SHARE IF NOT EXISTS MFGPULSE_DB_SHARE
  COMMENT = 'Cross-account share of the entire MFGPULSE_DB database';

--------------------------------------------------------------------------
-- 2. GRANT DATABASE & SCHEMA USAGE TO THE SHARE
--------------------------------------------------------------------------
GRANT USAGE ON DATABASE MFGPULSE_DB TO SHARE MFGPULSE_DB_SHARE;

GRANT USAGE ON SCHEMA MFGPULSE_DB.AGENT       TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.ANALYTICS   TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.CURATED     TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.ML_FEATURES TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.ML_MODELS   TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.PUBLIC       TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.RAW_IT      TO SHARE MFGPULSE_DB_SHARE;
GRANT USAGE ON SCHEMA MFGPULSE_DB.RAW_OT      TO SHARE MFGPULSE_DB_SHARE;

--------------------------------------------------------------------------
-- 3. GRANT SELECT ON ALL TABLES IN EACH SCHEMA
--------------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.AGENT       TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.ANALYTICS   TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.CURATED     TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.ML_FEATURES TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.ML_MODELS   TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.PUBLIC       TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.RAW_IT      TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA MFGPULSE_DB.RAW_OT      TO SHARE MFGPULSE_DB_SHARE;

-- Grant SELECT on all views as well
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.AGENT       TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.ANALYTICS   TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.CURATED     TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.ML_FEATURES TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.ML_MODELS   TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.PUBLIC       TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.RAW_IT      TO SHARE MFGPULSE_DB_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA MFGPULSE_DB.RAW_OT      TO SHARE MFGPULSE_DB_SHARE;

--------------------------------------------------------------------------
-- 4. ADD CONSUMER ACCOUNT(S) TO THE SHARE
--    Replace MRREAYA-HJ25985 with the target account identifier.
--------------------------------------------------------------------------
ALTER SHARE MFGPULSE_DB_SHARE ADD ACCOUNTS = MRREAYA.HJ25985;

--------------------------------------------------------------------------
-- 5. REPLICATION GROUP (DATABASE + SHARE)
--    Bundles the database and its share into a single replication unit
--    so both replicate together to the target account.
--------------------------------------------------------------------------
-- CREATE REPLICATION GROUP IF NOT EXISTS MFGPULSE_REPLICATION_GROUP
--   OBJECT_TYPES = DATABASES, SHARES
--   ALLOWED_DATABASES = MFGPULSE_DB
--   ALLOWED_SHARES    = MFGPULSE_DB_SHARE
--   ALLOWED_ACCOUNTS  = MRREAYA.HJ25985
--   REPLICATION_SCHEDULE = '10 MINUTE';

--------------------------------------------------------------------------
-- 7. PROVIDER-SIDE VERIFICATION
--------------------------------------------------------------------------

-- Confirm the share exists and see consumer accounts
SHOW SHARES LIKE 'MFGPULSE_DB_SHARE';

-- Confirm all grants on the share
SHOW GRANTS TO SHARE MFGPULSE_DB_SHARE;

-- Confirm replication group configuration
SHOW REPLICATION GROUPS;

-- Confirm databases in the replication group (group-aware, not legacy)
SHOW DATABASES IN REPLICATION GROUP MFGPULSE_REPLICATION_GROUP;

-- Confirm shares in the replication group
SHOW SHARES IN REPLICATION GROUP MFGPULSE_REPLICATION_GROUP;

/*==========================================================================
  CONSUMER-SIDE VERIFICATION (run on the target/consumer account)
  --------------------------------------------------------------------------
  
  -- 1. Verify the inbound share is visible
  SHOW SHARES;
  
  -- 2. Create a database from the share
  CREATE DATABASE IF NOT EXISTS MFGPULSE_DB_SHARED
    FROM SHARE QEIPXIJ.NB44213.MFGPULSE_DB_SHARE;
  
  -- 3. Grant access to a role for querying
  GRANT IMPORTED PRIVILEGES ON DATABASE MFGPULSE_DB_SHARED TO ROLE SYSADMIN;
  
  -- 4. Verify data is accessible
  USE DATABASE MFGPULSE_DB_SHARED;
  SHOW SCHEMAS;
  SELECT * FROM RAW_OT.SENSOR_READINGS LIMIT 10;
  
  -- 5. Create a secondary replication group (for failover)
  CREATE REPLICATION GROUP MFGPULSE_REPLICATION_GROUP
    AS REPLICA OF QEIPXIJ.NB44213.MFGPULSE_REPLICATION_GROUP;
  
  -- 6. Manually refresh (or wait for the scheduled refresh)
  ALTER REPLICATION GROUP MFGPULSE_REPLICATION_GROUP REFRESH;
  
==========================================================================*/