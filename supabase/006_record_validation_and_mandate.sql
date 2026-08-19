update public.dep_mlb_runs set run_status='COMPLETED', closed_at=now(), metadata=metadata || jsonb_build_object('validation_result','FULL_INFRA_CHAIN_PASS','sports_analysis',false) where run_id='TEST-DEP-V02';
update public.dep_mlb_connector_registry set metadata = metadata || jsonb_build_object('official_mlb_source_bridge_test','PASS','verified_source','MLB.com schedule','verified_on','2026-08-19') where connector_name='Web';
update public.agent_registry set metadata = metadata || jsonb_build_object(
  'connected_mandate_document_id','1ML5TWbb1uNGbjFj52FlaEUV14Qai_iwp8qs3OOB_d4Q',
  'controlled_validation_run_id','TEST-DEP-V02',
  'controlled_validation_result','FULL_INFRA_CHAIN_PASS',
  'official_mlb_web_bridge_verified',true,
  'standalone_http_kernel_fail_closed',true
), updated_at=now() where agent_id='@DepuracionMLB';
