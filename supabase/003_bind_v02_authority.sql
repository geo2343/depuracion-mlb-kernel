update public.agent_registry
set mother_document_sha256='e5b8272192faf2b06526066ded66fb131ea21a33cc30baee7a127c0e2ff18482',
    metadata = metadata || jsonb_build_object(
      'mother_hash_basis','plain-text export after CONNECTED_AGENT_MIGRATION_NOTICE V0.2 verified 2026-08-19',
      'canonical_mother_revision_state','V0.3 methodology + V0.2 execution migration notice',
      'connected_runtime_folder_id','11YDWJAfQ_XJk5yT1t2fvvWB80KU-wr-n',
      'connected_status_document_id','1rIVa0hmEq2enoux227v7eoY48gY9Az0fCHzFNPQ_hlA'
    ),
    updated_at=now()
where agent_id='@DepuracionMLB';
