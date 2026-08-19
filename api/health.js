export default function handler(req, res) {
  res.status(200).json({
    service: 'DepuracionMLB-Kernel',
    status: 'OK',
    external: true,
    version: '0.1.0'
  });
}
