/*=============================================================================
  01_admin_setup.sql: ONE-TIME admin setup. Run as ACCOUNTADMIN in a worksheet.
  DCM does not run this file. Safe to re-run.

  Creates:
    1. DCM_ADMIN database (home of the four DCM project objects) + admin warehouse
    2. Network rule + external access integration for api.census.gov
       (external access integrations are not a DEFINE type in DCM yet)
    3. Per environment: a deployer role and a GitHub OIDC service user.
       No passwords or keys: GitHub's identity token is the credential, and it
       is only accepted from this repo AND the matching GitHub Environment.

  If you rename the repo, update the SUBJECT lines in section 3.
=============================================================================*/

USE ROLE ACCOUNTADMIN;

----------------------------------------------------------------------
-- 1. Admin home for the DCM project objects
--    (the plan action runs "snow dcm create --if-not-exists" for you)
----------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS DCM_ADMIN_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Used by the DCM deployer service users for plan/deploy';

CREATE DATABASE IF NOT EXISTS DCM_ADMIN
    COMMENT = 'DCM POC: DCM project objects and shared integrations';
CREATE SCHEMA IF NOT EXISTS DCM_ADMIN.PROJECTS;
CREATE SCHEMA IF NOT EXISTS DCM_ADMIN.INTEGRATIONS;

----------------------------------------------------------------------
-- 2. Outbound access to the Census API (used by SP_LOAD_ACS_FROM_API)
--    To skip the API piece: skip this section, skip the three
--    integration/schema/secret grant lines per environment below, and set
--    enable_census_api: false in dcm/manifest.yml.
----------------------------------------------------------------------
CREATE NETWORK RULE IF NOT EXISTS DCM_ADMIN.INTEGRATIONS.CENSUS_API_EGRESS
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('api.census.gov:443');

-- The Census API requires a free key: https://api.census.gov/data/key_signup.html
-- Paste it below. To change it later:
--   ALTER SECRET DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY SET SECRET_STRING = '<new key>';
CREATE SECRET IF NOT EXISTS DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY
    TYPE = GENERIC_STRING
    SECRET_STRING = 'PASTE_YOUR_CENSUS_API_KEY_HERE'
    COMMENT = 'Census Bureau API key used by SP_LOAD_ACS_FROM_API';

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS CENSUS_API_ACCESS
    ALLOWED_NETWORK_RULES = (DCM_ADMIN.INTEGRATIONS.CENSUS_API_EGRESS)
    ALLOWED_AUTHENTICATION_SECRETS = (DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY)
    ENABLED = TRUE
    COMMENT = 'DCM POC: HTTPS egress to api.census.gov';

----------------------------------------------------------------------
-- 3. One deployer role + one OIDC service user per environment
--    Role DCM_DEPLOYER_<ENV>  = project_owner in dcm/manifest.yml
--    User SVC_GH_DCM_<ENV>    = SNOWFLAKE_USER in the workflows
----------------------------------------------------------------------

-- ---------------- DEV ----------------
CREATE ROLE IF NOT EXISTS DCM_DEPLOYER_DEV
    COMMENT = 'Owns and deploys every object in the DEV DCM project';
GRANT ROLE DCM_DEPLOYER_DEV TO ROLE SYSADMIN;   -- so you can see/query its objects

GRANT CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE ON ACCOUNT TO ROLE DCM_DEPLOYER_DEV;
GRANT EXECUTE TASK ON ACCOUNT                         TO ROLE DCM_DEPLOYER_DEV;
GRANT USAGE ON DATABASE DCM_ADMIN                     TO ROLE DCM_DEPLOYER_DEV;
GRANT USAGE, CREATE DCM PROJECT, CREATE STAGE
    ON SCHEMA DCM_ADMIN.PROJECTS                      TO ROLE DCM_DEPLOYER_DEV;
GRANT USAGE ON WAREHOUSE DCM_ADMIN_WH                 TO ROLE DCM_DEPLOYER_DEV;
GRANT USAGE ON INTEGRATION CENSUS_API_ACCESS          TO ROLE DCM_DEPLOYER_DEV;
GRANT USAGE ON SCHEMA DCM_ADMIN.INTEGRATIONS          TO ROLE DCM_DEPLOYER_DEV;
GRANT READ ON SECRET DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY TO ROLE DCM_DEPLOYER_DEV;

CREATE OR REPLACE USER SVC_GH_DCM_DEV
    TYPE = SERVICE
    DEFAULT_ROLE = DCM_DEPLOYER_DEV
    DEFAULT_WAREHOUSE = DCM_ADMIN_WH
    COMMENT = 'GitHub Actions deployer for DCM_DEV (OIDC, no password)'
    WORKLOAD_IDENTITY = (
        TYPE = OIDC
        ISSUER = 'https://token.actions.githubusercontent.com'
        SUBJECT = 'repo:RaghavendarRB/snowflake-dcm-poc:environment:DCM_DEV'
    );
GRANT ROLE DCM_DEPLOYER_DEV TO USER SVC_GH_DCM_DEV;

-- ---------------- QA ----------------
CREATE ROLE IF NOT EXISTS DCM_DEPLOYER_QA
    COMMENT = 'Owns and deploys every object in the QA DCM project';
GRANT ROLE DCM_DEPLOYER_QA TO ROLE SYSADMIN;   -- so you can see/query its objects

GRANT CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE ON ACCOUNT TO ROLE DCM_DEPLOYER_QA;
GRANT EXECUTE TASK ON ACCOUNT                         TO ROLE DCM_DEPLOYER_QA;
GRANT USAGE ON DATABASE DCM_ADMIN                     TO ROLE DCM_DEPLOYER_QA;
GRANT USAGE, CREATE DCM PROJECT, CREATE STAGE
    ON SCHEMA DCM_ADMIN.PROJECTS                      TO ROLE DCM_DEPLOYER_QA;
GRANT USAGE ON WAREHOUSE DCM_ADMIN_WH                 TO ROLE DCM_DEPLOYER_QA;
GRANT USAGE ON INTEGRATION CENSUS_API_ACCESS          TO ROLE DCM_DEPLOYER_QA;
GRANT USAGE ON SCHEMA DCM_ADMIN.INTEGRATIONS          TO ROLE DCM_DEPLOYER_QA;
GRANT READ ON SECRET DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY TO ROLE DCM_DEPLOYER_QA;

CREATE OR REPLACE USER SVC_GH_DCM_QA
    TYPE = SERVICE
    DEFAULT_ROLE = DCM_DEPLOYER_QA
    DEFAULT_WAREHOUSE = DCM_ADMIN_WH
    COMMENT = 'GitHub Actions deployer for DCM_QA (OIDC, no password)'
    WORKLOAD_IDENTITY = (
        TYPE = OIDC
        ISSUER = 'https://token.actions.githubusercontent.com'
        SUBJECT = 'repo:RaghavendarRB/snowflake-dcm-poc:environment:DCM_QA'
    );
GRANT ROLE DCM_DEPLOYER_QA TO USER SVC_GH_DCM_QA;

-- ---------------- PREPROD ----------------
CREATE ROLE IF NOT EXISTS DCM_DEPLOYER_PREPROD
    COMMENT = 'Owns and deploys every object in the PREPROD DCM project';
GRANT ROLE DCM_DEPLOYER_PREPROD TO ROLE SYSADMIN;   -- so you can see/query its objects

GRANT CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE ON ACCOUNT TO ROLE DCM_DEPLOYER_PREPROD;
GRANT EXECUTE TASK ON ACCOUNT                         TO ROLE DCM_DEPLOYER_PREPROD;
GRANT USAGE ON DATABASE DCM_ADMIN                     TO ROLE DCM_DEPLOYER_PREPROD;
GRANT USAGE, CREATE DCM PROJECT, CREATE STAGE
    ON SCHEMA DCM_ADMIN.PROJECTS                      TO ROLE DCM_DEPLOYER_PREPROD;
GRANT USAGE ON WAREHOUSE DCM_ADMIN_WH                 TO ROLE DCM_DEPLOYER_PREPROD;
GRANT USAGE ON INTEGRATION CENSUS_API_ACCESS          TO ROLE DCM_DEPLOYER_PREPROD;
GRANT USAGE ON SCHEMA DCM_ADMIN.INTEGRATIONS          TO ROLE DCM_DEPLOYER_PREPROD;
GRANT READ ON SECRET DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY TO ROLE DCM_DEPLOYER_PREPROD;

CREATE OR REPLACE USER SVC_GH_DCM_PREPROD
    TYPE = SERVICE
    DEFAULT_ROLE = DCM_DEPLOYER_PREPROD
    DEFAULT_WAREHOUSE = DCM_ADMIN_WH
    COMMENT = 'GitHub Actions deployer for DCM_PREPROD (OIDC, no password)'
    WORKLOAD_IDENTITY = (
        TYPE = OIDC
        ISSUER = 'https://token.actions.githubusercontent.com'
        SUBJECT = 'repo:RaghavendarRB/snowflake-dcm-poc:environment:DCM_PREPROD'
    );
GRANT ROLE DCM_DEPLOYER_PREPROD TO USER SVC_GH_DCM_PREPROD;

-- ---------------- PROD ----------------
CREATE ROLE IF NOT EXISTS DCM_DEPLOYER_PROD
    COMMENT = 'Owns and deploys every object in the PROD DCM project';
GRANT ROLE DCM_DEPLOYER_PROD TO ROLE SYSADMIN;   -- so you can see/query its objects

GRANT CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE ON ACCOUNT TO ROLE DCM_DEPLOYER_PROD;
GRANT EXECUTE TASK ON ACCOUNT                         TO ROLE DCM_DEPLOYER_PROD;
GRANT USAGE ON DATABASE DCM_ADMIN                     TO ROLE DCM_DEPLOYER_PROD;
GRANT USAGE, CREATE DCM PROJECT, CREATE STAGE
    ON SCHEMA DCM_ADMIN.PROJECTS                      TO ROLE DCM_DEPLOYER_PROD;
GRANT USAGE ON WAREHOUSE DCM_ADMIN_WH                 TO ROLE DCM_DEPLOYER_PROD;
GRANT USAGE ON INTEGRATION CENSUS_API_ACCESS          TO ROLE DCM_DEPLOYER_PROD;
GRANT USAGE ON SCHEMA DCM_ADMIN.INTEGRATIONS          TO ROLE DCM_DEPLOYER_PROD;
GRANT READ ON SECRET DCM_ADMIN.INTEGRATIONS.CENSUS_API_KEY TO ROLE DCM_DEPLOYER_PROD;

CREATE OR REPLACE USER SVC_GH_DCM_PROD
    TYPE = SERVICE
    DEFAULT_ROLE = DCM_DEPLOYER_PROD
    DEFAULT_WAREHOUSE = DCM_ADMIN_WH
    COMMENT = 'GitHub Actions deployer for DCM_PROD (OIDC, no password)'
    WORKLOAD_IDENTITY = (
        TYPE = OIDC
        ISSUER = 'https://token.actions.githubusercontent.com'
        SUBJECT = 'repo:RaghavendarRB/snowflake-dcm-poc:environment:DCM_PROD'
    );
GRANT ROLE DCM_DEPLOYER_PROD TO USER SVC_GH_DCM_PROD;

----------------------------------------------------------------------
-- 4. Copy this value into account_identifier (all four targets) in
--    dcm/manifest.yml
----------------------------------------------------------------------
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS ACCOUNT_IDENTIFIER;
