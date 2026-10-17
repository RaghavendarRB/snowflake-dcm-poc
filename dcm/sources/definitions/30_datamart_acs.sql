/*=============================================================================
  30_datamart_acs.sql: datamart layer, the view consumers query.
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

define view {{db}}_DATAMART.EDP_ACS.V_COUNTY_PROFILE
comment = 'County profile: population share and income band, with region'
as
select
    i.GEOID,
    i.COUNTY_NAME,
    coalesce(r.REGION, 'Unassigned')                       as REGION,
    i.ACS_YEAR,
    i.TOTAL_POPULATION,
    round(100 * i.TOTAL_POPULATION
        / nullif(sum(i.TOTAL_POPULATION) over (partition by i.ACS_YEAR), 0), 2)
                                                           as PCT_OF_STATE_POPULATION,
    i.MEDIAN_HH_INCOME,
    case
        when i.MEDIAN_HH_INCOME is null    then 'Not available'
        when i.MEDIAN_HH_INCOME >= 100000  then 'High'
        when i.MEDIAN_HH_INCOME >= 75000   then 'Middle'
        else 'Lower'
    end                                                    as INCOME_BAND
from {{db}}_CURATED.EDP_ACS.ACS_COUNTY_INDICATORS i
left join {{db}}_CURATED.EDP_ACS.REF_COUNTY_REGION r
    on r.GEOID = i.GEOID
;
