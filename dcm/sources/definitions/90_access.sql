/*=============================================================================
  90_access.sql: read-only role for consumers of the datamart.

  Grants are declared too, so a grant removed here is revoked on the next
  deploy (no more grants drifting between environments).
=============================================================================*/
{% set db = db_prefix ~ '_' ~ env %}

define role {{db}}_READER
    comment = 'Read access to the {{env}} datamart'
;

grant usage on warehouse {{db}}_WH                          to role {{db}}_READER;
grant usage on database {{db}}_DATAMART                     to role {{db}}_READER;
grant usage on schema {{db}}_DATAMART.EDP_ACS               to role {{db}}_READER;
grant select on view {{db}}_DATAMART.EDP_ACS.V_COUNTY_PROFILE to role {{db}}_READER;

-- Keep the new role inside the deployer's hierarchy (the deployer rolls up to SYSADMIN).
grant role {{db}}_READER to role {{project_owner_role}};
