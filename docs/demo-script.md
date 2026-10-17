# Demo script

A walkthrough for presenting the POC, about 20 minutes. Each scenario maps to a
problem the team hits today with V-numbered schemachange scripts. Do the setup
in the README first, and run one full promotion beforehand so all four
environments exist.

---

## Scenario 1: A change flows to every environment without version numbers

**Today's pain:** a new `V*.sql` per change, and tracking which version ran where.

1. Create a branch and add a column to the curated table in
   `dcm/sources/definitions/20_curated_acs.sql`:

   ```sql
   define table {{db}}_CURATED.EDP_ACS.ACS_COUNTY_INDICATORS (
       ...
       UPDATED_AT        TIMESTAMP_LTZ,
       DATA_SOURCE       VARCHAR DEFAULT 'Census ACS 5-year'   -- new, added last
   )
   ```

   Add new columns at the end: DCM alters tables in place and doesn't reorder
   columns.

2. Open a PR. Show the four plan comments: each says
   `ALTER TABLE ... ACS_COUNTY_INDICATORS` with the added column.
   **Point:** the same code produces a reviewed diff for every environment.

3. Merge. Show **2) Promote on merge** running DEV → QA, pausing for the
   PREPROD approval, then PROD.

4. In Snowflake, show the column exists in all four environments and the
   existing rows are still there. No version table to check.

## Scenario 2: Changing logic that is already deployed

**Today's pain:** editing a deployed `V2` does nothing; it must become `V3`.

1. On a branch, change the income bands in
   `dcm/sources/definitions/30_datamart_acs.sql` (for example `>= 90000` for High).
2. Open a PR. The plan shows `ALTER VIEW ... V_COUNTY_PROFILE`.
3. Merge and promote. **Point:** you edited the object where it lives; there is
   no second file to create and nothing to remember.

## Scenario 3: Rollback

**Today's pain:** rerunning V1 doesn't undo V2.

1. In GitHub, open the merged PR from scenario 2 and click **Revert**. This
   opens a new PR.
2. The plan comments show the ALTER back to the previous bands.
3. Merge. **Point:** rollback is a normal, reviewed change.

## Scenario 4: Drift (someone changed an environment by hand)

1. In Snowflake, change something by hand (`SYSADMIN` inherits the deployer
   roles, so it can):

   ```sql
   USE ROLE SYSADMIN;
   REVOKE SELECT ON VIEW POC_QA_DATAMART.EDP_ACS.V_COUNTY_PROFILE FROM ROLE POC_QA_READER;
   ```

2. Run **3) Deploy one environment** for `DCM_QA`. The plan in the job summary
   shows the grant being restored.
   **Point:** environments can't silently diverge from Git.

## Scenario 5: Python procedure calling an external API

**This was the reason DCM was ruled out.**

1. Show `SP_LOAD_ACS_FROM_API` in `dcm/sources/definitions/10_landing_acs.sql`:
   a Python handler, `requests`, and an external access integration, all in a
   DCM definition.
2. Run **4) Run ACS load** for `DCM_DEV`. The job log ends with the county
   profile from the datamart view.
3. **Be clear about the boundary:** the external access integration itself is a
   one-time admin object (`setup/01_admin_setup.sql`); DCM doesn't define
   integrations yet. The procedure, its tables and its downstream objects are
   all DCM-managed.

## Scenario 6: Safety net against dropping data

1. On a branch, delete the `REF_COUNTY_REGION` table definition from
   `20_curated_acs.sql` (and its join in the view).
2. The PR plan shows `DROP TABLE`. If merged, the DEV deploy **fails on purpose**
   because the plan contains a table drop.
3. Close the PR without merging. **Point:** destructive changes need an
   explicit, separate decision (workflow 3 with *allow_drops*).

---

## Summary slide

- One definition per object, no version numbers, no history table to check.
- Every change is planned and reviewed per environment before it deploys.
- Rollback = revert; drift is detected and corrected.
- No credentials stored anywhere (GitHub OIDC).
- Python procedures with external API calls work; the external access
  integration stays a one-time admin step.
- Still needed outside DCM: data loads/CALLs, and planned migrations for
  incompatible column changes.
