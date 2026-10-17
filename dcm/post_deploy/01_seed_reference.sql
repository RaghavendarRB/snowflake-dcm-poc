-- Post-deploy script: runs after every successful DCM deploy (dcm/deploy action,
-- post-scripts-path: post_deploy). Jinja vars from manifest.yml are available.
--
-- DCM manages object STRUCTURE. Data changes (seed rows, CALLs, backfills) live
-- here or in a run workflow, and must be safe to run repeatedly, hence MERGE.

merge into {{db_prefix}}_{{env}}_CURATED.EDP_ACS.REF_COUNTY_REGION t
using (
    select column1 as GEOID, column2 as COUNTY_NAME, column3 as REGION
    from values
        ('25001', 'Barnstable County', 'Cape and Islands'),
        ('25003', 'Berkshire County',  'Western'),
        ('25005', 'Bristol County',    'Southeast'),
        ('25007', 'Dukes County',      'Cape and Islands'),
        ('25009', 'Essex County',      'Northeast'),
        ('25011', 'Franklin County',   'Western'),
        ('25013', 'Hampden County',    'Western'),
        ('25015', 'Hampshire County',  'Western'),
        ('25017', 'Middlesex County',  'Greater Boston'),
        ('25019', 'Nantucket County',  'Cape and Islands'),
        ('25021', 'Norfolk County',    'Greater Boston'),
        ('25023', 'Plymouth County',   'Southeast'),
        ('25025', 'Suffolk County',    'Greater Boston'),
        ('25027', 'Worcester County',  'Central')
) s
on t.GEOID = s.GEOID
when matched and (t.COUNTY_NAME <> s.COUNTY_NAME or t.REGION <> s.REGION) then update set
    t.COUNTY_NAME = s.COUNTY_NAME,
    t.REGION      = s.REGION
when not matched then insert (GEOID, COUNTY_NAME, REGION)
    values (s.GEOID, s.COUNTY_NAME, s.REGION);
