-- ============================================================
-- Single-Shot Setup: Git-Integrated Workspace (GitHub)
-- ============================================================
-- Run this entire script as ACCOUNTADMIN (or a role with
-- CREATE INTEGRATION + CREATE SECRET privileges).
--
-- After running, create the workspace in the Snowsight UI:
--   Projects >> Workspaces >> From Git repository
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================
-- OPTION A: OAuth via Snowflake GitHub App (recommended)
-- Simplest path — no secret needed, browser-based sign-in.
-- ============================================================

CREATE API INTEGRATION IF NOT EXISTS github_oauth_integration
  API_PROVIDER         = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/<your-org-or-user>')  -- e.g. 'https://github.com/MFGPulse'
  ENABLED              = TRUE;

-- That's it for OAuth. When creating the workspace in the UI,
-- select this integration, pick "OAuth2", and sign in via browser.
-- The Snowflake GitHub App handles token exchange automatically.


-- ============================================================
-- OPTION B: Personal Access Token (PAT)
-- Use when OAuth isn't available or for headless/service setups.
-- ============================================================

-- B1. Create a database + schema to hold the secret (skip if you have one)
CREATE DATABASE IF NOT EXISTS ADMIN_DB;
CREATE SCHEMA  IF NOT EXISTS ADMIN_DB.INTEGRATIONS;

-- B2. Store the GitHub PAT as a Snowflake secret
--     Generate a fine-grained PAT at https://github.com/settings/tokens
--     with "Contents: Read and write" permission on your repo(s).
CREATE OR REPLACE SECRET ADMIN_DB.INTEGRATIONS.GITHUB_PAT_SECRET
  TYPE            = PASSWORD
  USERNAME        = '<your-github-username>'         -- e.g. 'abik'
  PASSWORD        = '<your-github-pat>';             -- e.g. 'ghp_xxxxxxxxxxxx'

-- B3. Create the API integration referencing the secret
CREATE OR REPLACE API INTEGRATION github_pat_integration
  API_PROVIDER                 = git_https_api
  API_ALLOWED_PREFIXES         = ('https://github.com/<your-org-or-user>')
  ALLOWED_AUTHENTICATION_SECRETS = (ADMIN_DB.INTEGRATIONS.GITHUB_PAT_SECRET)
  ENABLED                      = TRUE;


-- ============================================================
-- GRANT USAGE so non-admin roles can use the integration
-- ============================================================

-- Replace SYSADMIN with whatever role your workspace users have
GRANT USAGE ON INTEGRATION github_oauth_integration TO ROLE SYSADMIN;
-- or for PAT:
GRANT USAGE ON INTEGRATION github_pat_integration   TO ROLE SYSADMIN;

-- If using PAT, also grant read on the secret
GRANT USAGE ON DATABASE ADMIN_DB                              TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA   ADMIN_DB.INTEGRATIONS                TO ROLE SYSADMIN;
GRANT READ  ON SECRET   ADMIN_DB.INTEGRATIONS.GITHUB_PAT_SECRET TO ROLE SYSADMIN;


-- ============================================================
-- VERIFY
-- ============================================================
SHOW INTEGRATIONS LIKE '%github%';
-- Expect: github_oauth_integration and/or github_pat_integration


-- ============================================================
-- NEXT STEP (UI only — no SQL equivalent)
-- ============================================================
-- 1. Go to Snowsight >> Projects >> Workspaces
-- 2. Click "From Git repository"
-- 3. Paste your repo URL: https://github.com/<org>/<repo>
-- 4. Name the workspace (e.g. MFGPulse_AI)
-- 5. Select the API integration created above
-- 6. For OAuth: click "Sign in" and authorize in browser
--    For PAT:  select the secret (ADMIN_DB.INTEGRATIONS.GITHUB_PAT_SECRET)
-- 7. Click "Create"
--
-- You can now push, pull, and branch directly from the workspace.
-- ============================================================
