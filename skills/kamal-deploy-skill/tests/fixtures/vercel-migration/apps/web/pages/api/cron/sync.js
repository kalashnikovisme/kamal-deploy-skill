export default function handler(req, res) {
  // Reads from Vercel KV; the actual URL/token are never in this repo.
  const kvUrl = process.env.KV_REST_API_URL
  res.status(200).json({ synced: Boolean(kvUrl) })
}
