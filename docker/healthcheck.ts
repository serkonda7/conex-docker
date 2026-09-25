// Container healthcheck: exits 0 when the API answers GET /health.
const port = process.env.CONEX_SERVER_PORT ?? '3000'

try {
	const res = await fetch(`http://127.0.0.1:${port}/health`, {
		signal: AbortSignal.timeout(4000),
	})
	process.exit(res.ok ? 0 : 1)
} catch {
	process.exit(1)
}
