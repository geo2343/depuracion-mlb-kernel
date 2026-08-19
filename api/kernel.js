import crypto from 'crypto';

const FLOW = ['T1_IDENTITY', 'T2_STARTER_SCREEN', 'T3_OFFENSE_SCREEN'];

export default async function handler(req, res) {
  const task = String(req.query.task || '');
  const expected = FLOW[0];

  if (task !== expected) {
    return res.status(409).json({
      accepted: false,
      error: 'TASK_NOT_AUTHORIZED',
      expected,
      received: task
    });
  }

  const evidence_id = 'EV-' + crypto
    .createHash('sha256')
    .update(`${task}|${Date.now()}|${crypto.randomUUID()}`)
    .digest('hex')
    .slice(0, 12)
    .toUpperCase();

  return res.status(200).json({
    accepted: true,
    task,
    evidence_id,
    generated_by: 'external_kernel',
    note: 'Demo control endpoint. MLB source integration not yet enabled.'
  });
}
