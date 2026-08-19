export default async function handler(req, res) {
  return res.status(503).json({
    accepted: false,
    service: 'DepuracionMLB-Kernel',
    version: '0.2.0',
    agent: '@DepuracionMLB',
    error: 'STANDALONE_MLB_BRIDGE_NOT_READY',
    detail: 'This HTTP endpoint must not fabricate evidence. Connected execution currently uses verified ChatGPT connectors plus Supabase/Drive lineage. Enable this endpoint only after a real MLB source bridge and deployment are physically verified.',
    evidence_generated: false,
    vercel_deployment_verified: false,
    real_money_authority: false
  });
}
