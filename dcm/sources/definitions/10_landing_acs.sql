/*=============================================================================
  10_landing_acs.sql: landing layer for the ACS dataset.

  - ACS_COUNTY_RAW: raw Census API output, kept as text (like a COPY target).
  - CSV_FORMAT + ACS_FILES: internal stage for manual PUT/COPY loads.
  - SP_LOAD_ACS_FROM_API: Python procedure that calls the Census API through an
    external access integration. This is the pattern (Python + external API)
    that DCM did not support when the team last evaluated it.

  Note: DCM defines the procedure. The network rule, the API-key secret and
  the external access integration are created once by an admin
  (setup/01_admin_setup.sql): external access integrations are not a DEFINE
  type in DCM yet, and the key must never be committed to Git.
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

define table {{db}}_LANDING.EDP_ACS.ACS_COUNTY_RAW (
    COUNTY_NAME       VARCHAR,
    TOTAL_POPULATION  VARCHAR,
    MEDIAN_HH_INCOME  VARCHAR,
    STATE_FIPS        VARCHAR,
    COUNTY_FIPS       VARCHAR,
    ACS_YEAR          NUMBER(4,0),
    LOADED_AT         TIMESTAMP_LTZ
)
comment = 'Raw ACS 5-year county estimates as returned by the Census API (text columns)'
;

define file format {{db}}_LANDING.EDP_ACS.CSV_FORMAT
    TYPE = 'csv'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null')
    EMPTY_FIELD_AS_NULL = true
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
;

define stage {{db}}_LANDING.EDP_ACS.ACS_FILES
    directory = ( enable = true )
    comment = 'Internal stage for manual CSV loads (PUT + COPY INTO)'
;

{% if enable_census_api %}
define procedure {{db}}_LANDING.EDP_ACS.SP_LOAD_ACS_FROM_API(ACS_YEAR NUMBER)
returns STRING
language PYTHON
runtime_version = '3.11'
packages = ('snowflake-snowpark-python', 'requests')
handler = 'run'
external_access_integrations = ({{census_eai}})
secrets = ('census_key' = {{census_secret}})
comment = 'Loads ACS 5-year county population and median household income from api.census.gov'
execute as owner
as
$$
import _snowflake
import requests
from snowflake.snowpark.functions import current_timestamp, lit

TARGET_TABLE = "{{db}}_LANDING.EDP_ACS.ACS_COUNTY_RAW"
STATE_FIPS = "{{census_state_fips}}"
VARIABLES = ["NAME", "B01003_001E", "B19013_001E"]  # name, total population, median household income


def run(session, acs_year):
    year = int(acs_year)
    response = requests.get(
        f"https://api.census.gov/data/{year}/acs/acs5",
        params={
            "get": ",".join(VARIABLES),
            "for": "county:*",
            "in": f"state:{STATE_FIPS}",
            "key": _snowflake.get_generic_secret_string("census_key"),
        },
        timeout=60,
    )
    response.raise_for_status()

    payload = response.json()
    header, rows = payload[0], payload[1:]
    col = {name: i for i, name in enumerate(header)}
    records = [
        (
            r[col["NAME"]],
            r[col["B01003_001E"]],
            r[col["B19013_001E"]],
            r[col["state"]],
            r[col["county"]],
        )
        for r in rows
    ]
    if not records:
        return f"No rows returned for ACS {year}"

    df = (
        session.create_dataframe(
            records,
            schema=["COUNTY_NAME", "TOTAL_POPULATION", "MEDIAN_HH_INCOME", "STATE_FIPS", "COUNTY_FIPS"],
        )
        .with_column("ACS_YEAR", lit(year))
        .with_column("LOADED_AT", current_timestamp())
    )

    # Re-runnable: replace the year being loaded, keep other years.
    session.sql(f"DELETE FROM {TARGET_TABLE} WHERE ACS_YEAR = ?", params=[year]).collect()
    df.write.mode("append").save_as_table(TARGET_TABLE, column_order="name")
    return f"Loaded {len(records)} county rows for ACS {year} into {TARGET_TABLE}"
$$
;
{% endif %}
