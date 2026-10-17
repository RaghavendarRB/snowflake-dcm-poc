/*=============================================================================
  00_infrastructure.sql: warehouse, databases and schemas for one environment.

  Mirrors the EDP layout: <PREFIX>_<ENV>_LANDING / _CURATED / _DATAMART,
  each with a dataset schema (EDP_ACS). DCM creates these on first deploy and
  ALTERs them in place afterwards; there are no version numbers to manage.
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

define warehouse {{db}}_WH
    with
    warehouse_size = '{{wh_size}}'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'DCM POC compute for {{env}}'
;

{% for layer in ['LANDING', 'CURATED', 'DATAMART'] %}
define database {{db}}_{{layer}}
    data_retention_time_in_days = {{data_retention_days}}
    comment = 'DCM POC {{env}} {{layer | lower}} layer'
;

define schema {{db}}_{{layer}}.EDP_ACS
    comment = 'American Community Survey (ACS) county indicators'
;
{% endfor %}
