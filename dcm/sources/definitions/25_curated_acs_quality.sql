/*=============================================================================
  25_curated_acs_quality.sql: data-quality checks for the curated ACS table.

  - ACS_DQ_RESULTS: one row per check per run (history of every run).
  - SP_CHECK_ACS_QUALITY: Python (Snowpark) procedure that runs the checks
    for one ACS year, records the results, and returns a JSON summary.

  Added through a normal PR: DCM plans a CREATE for the table and the
  procedure in every environment; no V-numbered script involved.
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

define table {{db}}_CURATED.EDP_ACS.ACS_DQ_RESULTS (
    RUN_ID      VARCHAR,
    RUN_AT      TIMESTAMP_LTZ,
    ACS_YEAR    NUMBER(4,0),
    CHECK_NAME  VARCHAR,
    EXPECTED    VARCHAR,
    ACTUAL      VARCHAR,
    PASSED      BOOLEAN
)
comment = 'Data-quality check results for ACS_COUNTY_INDICATORS, one row per check per run'
;

define procedure {{db}}_CURATED.EDP_ACS.SP_CHECK_ACS_QUALITY(ACS_YEAR NUMBER)
returns STRING
language PYTHON
runtime_version = '3.11'
packages = ('snowflake-snowpark-python')
handler = 'run'
comment = 'Runs data-quality checks on curated ACS data for one year; returns a JSON summary'
execute as owner
as
$$
import json
import uuid

from snowflake.snowpark.functions import current_timestamp

SCHEMA = "{{db}}_CURATED.EDP_ACS"
EXPECTED_COUNTIES = {{expected_counties}}


def run(session, acs_year):
    year = int(acs_year)

    metrics = session.sql(
        f"""
        SELECT COUNT(*)                                AS ROW_COUNT,
               COUNT_IF(TOTAL_POPULATION IS NULL)      AS NULL_POP,
               COUNT_IF(MEDIAN_HH_INCOME IS NULL)      AS NULL_INCOME,
               COALESCE(SUM(TOTAL_POPULATION), 0)      AS TOTAL_POP
        FROM {SCHEMA}.ACS_COUNTY_INDICATORS
        WHERE ACS_YEAR = ?
        """,
        params=[year],
    ).collect()[0]

    unmapped = session.sql(
        f"""
        SELECT COUNT(*) AS N
        FROM {SCHEMA}.ACS_COUNTY_INDICATORS i
        LEFT JOIN {SCHEMA}.REF_COUNTY_REGION r ON r.GEOID = i.GEOID
        WHERE i.ACS_YEAR = ? AND r.GEOID IS NULL
        """,
        params=[year],
    ).collect()[0]["N"]

    # (check name, expected, actual, passed)
    checks = [
        ("row_count",          f"= {EXPECTED_COUNTIES}", metrics["ROW_COUNT"],   metrics["ROW_COUNT"] == EXPECTED_COUNTIES),
        ("null_population",    "= 0",                    metrics["NULL_POP"],    metrics["NULL_POP"] == 0),
        ("null_median_income", "= 0",                    metrics["NULL_INCOME"], metrics["NULL_INCOME"] == 0),
        ("total_population",   "> 0",                    metrics["TOTAL_POP"],   metrics["TOTAL_POP"] > 0),
        ("unmapped_regions",   "= 0",                    unmapped,               unmapped == 0),
    ]

    run_id = str(uuid.uuid4())
    (
        session.create_dataframe(
            [(run_id, year, name, expected, str(actual), bool(passed)) for name, expected, actual, passed in checks],
            schema=["RUN_ID", "ACS_YEAR", "CHECK_NAME", "EXPECTED", "ACTUAL", "PASSED"],
        )
        .with_column("RUN_AT", current_timestamp())
        .write.mode("append")
        .save_as_table(f"{SCHEMA}.ACS_DQ_RESULTS", column_order="name")
    )

    failed = [name for name, _, _, passed in checks if not passed]
    return json.dumps({
        "run_id": run_id,
        "acs_year": year,
        "checks": len(checks),
        "passed": len(checks) - len(failed),
        "failed": failed,
    })
$$
;
