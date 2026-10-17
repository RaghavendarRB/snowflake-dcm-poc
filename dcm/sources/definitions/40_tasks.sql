/*=============================================================================
  40_tasks.sql: monthly task graph (load from API -> transform).

  All tasks in a graph must share one database and schema, so both live in
  the landing EDP_ACS schema. They deploy SUSPENDED by default
  (task_state in manifest.yml); set it to STARTED for an environment to
  schedule the pull. DCM resolves root/child ordering itself.
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

{% if enable_census_api %}
define task {{db}}_LANDING.EDP_ACS.TASK_LOAD_ACS
    warehouse = '{{db}}_WH'
    schedule = 'USING CRON 0 6 1 * * America/New_York'
    comment = 'Monthly: pull ACS county estimates from the Census API'
    {{task_state}}
as
    call {{db}}_LANDING.EDP_ACS.SP_LOAD_ACS_FROM_API({{acs_year}});

define task {{db}}_LANDING.EDP_ACS.TASK_TRANSFORM_ACS
    warehouse = '{{db}}_WH'
    comment = 'Runs after the load: MERGE landing into curated'
    after {{db}}_LANDING.EDP_ACS.TASK_LOAD_ACS
    {{task_state}}
as
    call {{db}}_CURATED.EDP_ACS.SP_TRANSFORM_ACS();
{% endif %}
