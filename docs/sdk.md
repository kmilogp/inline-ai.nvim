# SDK Notes (Summary)

This plugin uses the Opencode JS SDK. Key points from the SDK docs:

- Install: `npm install @opencode-ai/sdk`
- Start server + client: `createOpencode({ hostname, port, config })`
  - Defaults: host `127.0.0.1`, port `4096`, start timeout `5000ms`
- Client-only mode: `createOpencodeClient({ baseUrl })`
- Core calls: `client.session.create`, `client.session.prompt`, `client.global.health`
- Errors: SDK can throw; handle via try/catch or check `result.error`
- Structured output: pass `format: { type: "json_schema", schema, retryCount }` in prompt body
- Useful APIs: `client.config.providers`, `client.project.current`, `client.file.read`, `client.find.text`
