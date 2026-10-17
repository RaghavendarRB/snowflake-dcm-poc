/*=============================================================================
  20_curated_acs.sql: curated layer for the ACS dataset.

  - ACS_COUNTY_INDICATORS: typed, deduplicated indicators.
  - REF_COUNTY_REGION: small reference table; its rows are seeded by
    post_deploy/01_seed_reference.sql (DCM manages structure, not data).
  - SP_TRANSFORM_ACS: SQL procedure that MERGEs landing into curated.

  To change transformation logic, edit SP_TRANSFORM_ACS here and open a PR.
  DCM plans an ALTER of the procedure; no new V-numbered script is needed.
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

define table {{db}}_CURATED.EDP_ACS.ACS_COUNTY_INDICATORS (
    GEOID             VARCHAR(5),
    STATE_FIPS        VARCHAR(2),
    COUNTY_FIPS       VARCHAR(3),
    COUNTY_NAME       VARCHAR,
    ACS_YEAR          NUMBER(4,0),
    TOTAL_POPULATION  NUMBER(12,0),
    MEDIAN_HH_INCOME  NUMBER(12,0),
    UPDATED_AT        TIMESTAMP_LTZ
)
comment = 'ACS county indicators, typed and deduplicated (one row per county per year)'
;

define table {{db}}_CURATED.EDP_ACS.REF_COUNTY_REGION (
    GEOID        VARCHAR(5),
    COUNTY_NAME  VARCHAR,
    REGION       VARCHAR
)
comment = 'Illustrative county-to-region grouping; rows seeded by a post-deploy script'
;

define procedure {{db}}_CURATED.EDP_ACS.SP_TRANSFORM_ACS()
returns VARCHAR
language SQL
execute as owner
as
$$
BEGIN
    MERGE INTO {{db}}_CURATED.EDP_ACS.ACS_COUNTY_INDICATORS t
    USING (
        SELECT
            STATE_FIPS || COUNTY_FIPS                         AS GEOID,
            STATE_FIPS,
            COUNTY_FIPS,
            SPLIT_PART(COUNTY_NAME, ',', 1)                   AS COUNTY_NAME,
            ACS_YEAR,
            TRY_TO_NUMBER(TOTAL_POPULATION)                   AS TOTAL_POPULATION,
            -- The Census API uses large negative codes for "not available".
            IFF(TRY_TO_NUMBER(MEDIAN_HH_INCOME) < 0, NULL,
                TRY_TO_NUMBER(MEDIAN_HH_INCOME))              AS MEDIAN_HH_INCOME
        FROM {{db}}_LANDING.EDP_ACS.ACS_COUNTY_RAW
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY STATE_FIPS, COUNTY_FIPS, ACS_YEAR
            ORDER BY LOADED_AT DESC
        ) = 1
    ) s
    ON t.GEOID = s.GEOID AND t.ACS_YEAR = s.ACS_YEAR
    WHEN MATCHED THEN UPDATE SET
        t.COUNTY_NAME      = s.COUNTY_NAME,
        t.TOTAL_POPULATION = s.TOTAL_POPULATION,
        t.MEDIAN_HH_INCOME = s.MEDIAN_HH_INCOME,
        t.UPDATED_AT       = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (GEOID, STATE_FIPS, COUNTY_FIPS, COUNTY_NAME, ACS_YEAR, TOTAL_POPULATION, MEDIAN_HH_INCOME, UPDATED_AT)
    VALUES
        (s.GEOID, s.STATE_FIPS, s.COUNTY_FIPS, s.COUNTY_NAME, s.ACS_YEAR, s.TOTAL_POPULATION, s.MEDIAN_HH_INCOME, CURRENT_TIMESTAMP());

    RETURN 'Merged ' || SQLROWCOUNT || ' rows into {{db}}_CURATED.EDP_ACS.ACS_COUNTY_INDICATORS';
END;
$$
;
