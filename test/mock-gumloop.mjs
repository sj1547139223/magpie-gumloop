// A stand-in for Gumloop (models + chat completions) and OpenRouter (prices),
// for testing the plugin in a sandbox magpie without a Gumloop account.
//
//   node test/mock-gumloop.mjs [port]
//
// Point the plugin at it with
//   GUMLOOP_API_BASE=http://127.0.0.1:<port>/api
//   GUMLOOP_WS_BASE=http://127.0.0.1:<port>/ws
//   GUMLOOP_OPENROUTER_BASE=http://127.0.0.1:<port>/or
//
// The test key and user id are below. GET /_log returns every chat request it
// got (headers and body); POST /_mode selects ok, credits, badkey,
// plan, upstream-credits or octet-stream.
// changes how chat answers; POST /_reset clears the log.
import * as http from "node:http"

export const KEY = "mock-key-AAAAAAAAAAAAAAAAAAAA"
export const USER = "mockuser1111"
const port = Number(process.argv[2] || 4810)

const opt = (value, label, caps, extra = {}) => ({
  value,
  label,
  status: "active",
  restricted: false,
  metadata: { capabilities: caps, context_window: 1000000, ...extra.metadata },
  ...extra.top,
})
const MODELS = {
  model_groups: [
    { groupLabel: "Auto", options: [opt("gumloop-chew", "Auto", ["functions"])] },
    {
      groupLabel: "Anthropic",
      options: [
        opt("claude-sonnet-5-5", "Claude Sonnet 5.5", ["functions", "vision"], { metadata: { short_context_window: 300000 } }),
        opt("claude-opus-5-5", "Claude Opus 5.5", ["functions", "vision"]),
        opt("claude-opus-4-8", "Claude Opus 4.8 (old)", ["functions"], { top: { status: "hidden" } }),
      ],
    },
    { groupLabel: "OpenAI", options: [opt("gpt-6-sol", "GPT-6 Sol", ["functions", "reasoning"], { metadata: { context_window: 272000 } })] },
    { groupLabel: "Fireworks", options: [opt("accounts/fireworks/models/glm-5p3", "GLM 5.3", ["functions", "reasoning"])] },
    { groupLabel: "Images", options: [opt("image-gen-1", "Image Gen", ["functions"], { top: { is_image_generation: true } })] },
  ],
}
const PRICES = {
  data: [
    { id: "anthropic/claude-sonnet-5.5", pricing: { prompt: "0.000003", completion: "0.000015", input_cache_read: "0.0000003", input_cache_write: "0.00000375" } },
    { id: "anthropic/claude-opus-5.5", pricing: { prompt: "0.000004", completion: "0.00002", input_cache_read: "0.0000004", input_cache_write: "0.000005" } },
    { id: "openai/gpt-6-sol", pricing: { prompt: "0.000002", completion: "0.00001", input_cache_read: "0.0000002" } },
    { id: "z-ai/glm-5.3", pricing: { prompt: "0.000000079", completion: "0.0000048" } },
  ],
}
const ENDPOINTS = {
  data: {
    endpoints: [
      { provider_name: "Wafer", pricing: { prompt: "0.000000079", completion: "0.0000048" } },
      { provider_name: "Fireworks", pricing: { prompt: "0.0000014", completion: "0.0000044", input_cache_read: "0.00000026" } },
    ],
  },
}
const USAGE = { prompt_tokens: 12000, completion_tokens: 800, total_tokens: 12800, prompt_tokens_details: { cached_tokens: 8000, cache_write_tokens: 2000 } }

let mode = "ok"
const log = []
const send = (res, status, body, type = "application/json") => {
  res.writeHead(status, { "content-type": type })
  res.end(typeof body === "string" ? body : JSON.stringify(body))
}
const authed = (req) => req.headers.authorization === `Bearer ${KEY}` && req.headers["x-auth-key"] === USER

http
  .createServer(async (req, res) => {
    const parts = []
    for await (const c of req) parts.push(c)
    const raw = Buffer.concat(parts).toString("utf8")
    const url = new URL(req.url, "http://x")
    const path = url.pathname

    if (path === "/_log") return send(res, 200, log)
    if (path === "/_reset") return (log.length = 0), send(res, 200, { ok: true })
    if (path === "/_mode") {
      mode = JSON.parse(raw || "{}").mode || "ok"
      return send(res, 200, { mode })
    }
    if (path === "/api/models") {
      if (!authed(req) || mode === "badkey") return send(res, 403, { error: "Invalid API key or user id" })
      return send(res, 200, MODELS)
    }
    if (path === "/or/models") return send(res, 200, PRICES)
    if (path === "/or/models/z-ai/glm-5.3/endpoints") return send(res, 200, ENDPOINTS)

    if (path === "/ws/chat/completions") {
      let body = {}
      try {
        body = JSON.parse(raw || "{}")
      } catch {}
      log.push({ at: Date.now(), headers: req.headers, body })
      if (!authed(req) || mode === "badkey") return send(res, 403, { error: "Invalid API key" })
      if (mode === "credits") return send(res, 403, { error: { code: "credit_limit_exceeded", message: "You have reached your credit limit." } })
      if (mode === "plan") return send(res, 403, { error: { message: "You are not authorized to use claude-opus-5-5 on your current plan" } })
      if (mode === "upstream-credits") return send(res, 400, { error: { message: "anthropic: Your credit balance is too low to access the Anthropic API." } })
      if (String(body.model).startsWith("claude-sonnet") && body.max_tokens > 64000) {
        return send(res, 400, { error: { code: "provider_error", message: `max_tokens: ${body.max_tokens} > 64000, which is the maximum allowed number of output tokens for ${body.model}` } })
      }
      const id = `chatcmpl-${log.length}`
      const reply = `pong from ${body.model}`
      if (body.stream) {
        res.writeHead(200, { "content-type": mode === "octet-stream" ? "application/octet-stream" : "text/event-stream; charset=utf-8" })
        const frame = (o) => `data: ${JSON.stringify(o)}\n\n`
        res.write(frame({ id, object: "chat.completion.chunk", model: body.model, choices: [{ index: 0, delta: { role: "assistant", content: "" } }] }))
        for (const w of reply.split(" ")) {
          res.write(frame({ id, object: "chat.completion.chunk", model: body.model, choices: [{ index: 0, delta: { content: w + " " } }] }))
        }
        res.write(frame({ id, object: "chat.completion.chunk", model: body.model, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] }))
        if (body.stream_options?.include_usage) res.write(frame({ id, object: "chat.completion.chunk", model: body.model, choices: [], usage: USAGE }))
        res.end("data: [DONE]\n\n")
        return
      }
      return send(res, 200, {
        id,
        object: "chat.completion",
        model: body.model,
        choices: [{ index: 0, message: { role: "assistant", content: reply }, finish_reason: "stop" }],
        usage: USAGE,
      })
    }
    send(res, 404, { error: `mock: no route ${req.method} ${path}` })
  })
  .listen(port, "127.0.0.1", () => console.log(`mock gumloop on http://127.0.0.1:${port}`))
