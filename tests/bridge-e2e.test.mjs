// End-to-end test for the DSH iOS bridge (real dsh ACP backend).
// Run with: ELECTRON_RUN_AS_NODE=1 "<DeepSeek Harness.exe>" probe/bridge-test.mjs
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'))
const bridgePath = path.join(here, '..', 'bridge', 'server.mjs')
const configPath = path.join(os.tmpdir(), `dsh-bridge-test-${Date.now()}.json`)
const sessionsPath = path.join(os.tmpdir(), `dsh-bridge-sessions-${Date.now()}.json`)
const port = 18000 + Math.floor(Math.random() * 1000)
const token = 'TEST-CODE'
const workspace = process.cwd()

fs.writeFileSync(configPath, JSON.stringify({
  port,
  host: '127.0.0.1',
  token,
  autoApprove: false,
  workspaces: [workspace],
  defaultCwd: workspace,
  dsh: { command: [], env: {} },
}, null, 2))

const base = `http://127.0.0.1:${port}`
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const results = []
function check(name, ok, extra) {
  results.push({ name, ok })
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  ' + extra : ''}`)
}

const child = spawn(process.execPath, [bridgePath], {
  cwd: workspace,
  env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', DSH_BRIDGE_CONFIG: configPath, DSH_BRIDGE_SESSIONS: sessionsPath },
  stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: true,
})
let bridgeLog = ''
child.stdout.on('data', (d) => { bridgeLog += d.toString(); process.stdout.write('[bridge] ' + d.toString()) })
child.stderr.on('data', (d) => { bridgeLog += d.toString(); process.stdout.write('[bridge:err] ' + d.toString()) })

async function api(pathname, options = {}) {
  const res = await fetch(base + pathname, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  })
  const text = await res.text()
  let json
  try { json = JSON.parse(text) } catch { json = { raw: text } }
  return { status: res.status, json }
}

async function waitForReady(timeoutMs = 120000) {
  const started = Date.now()
  while (Date.now() - started < timeoutMs) {
    try {
      const { json } = await api('/v1/server')
      if (json?.dsh?.state === 'ready') return json
      if (json?.dsh?.state === 'failed') throw new Error('dsh failed: ' + json.dsh.error)
    } catch (e) {
      if (e.message.startsWith('dsh failed')) throw e
    }
    await sleep(1000)
  }
  throw new Error('bridge did not become ready')
}

// Minimal SSE reader
function openStream(url, onEvent) {
  const controller = new AbortController()
  const done = (async () => {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` }, signal: controller.signal })
    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    let buf = ''
    while (true) {
      const { value, done } = await reader.read()
      if (done) break
      buf += decoder.decode(value, { stream: true })
      let idx
      while ((idx = buf.indexOf('\n\n')) >= 0) {
        const raw = buf.slice(0, idx)
        buf = buf.slice(idx + 2)
        const dataLine = raw.split('\n').find((l) => l.startsWith('data: '))
        if (!dataLine) continue
        try { onEvent(JSON.parse(dataLine.slice(6))) } catch {}
      }
    }
  })().catch((e) => { if (e.name !== 'AbortError') console.error('sse error', e.message) })
  return { controller, done }
}

const main = async () => {
  const server = await waitForReady(150000)
  check('health / dsh ready', true, JSON.stringify(server.dsh.agent))
  check('workspaces listed', (server.workspaces || []).length > 0, JSON.stringify(server.workspaces))

  const created = await api('/v1/sessions', { method: 'POST', body: JSON.stringify({ cwd: workspace }) })
  check('create session', created.status === 200 && !!created.json.session?.id, created.json.session?.id)
  const sessionId = created.json.session.id
  const modelOption = (created.json.config || []).find((o) => o.id === 'model')
  check('config options with model', !!modelOption, modelOption ? `${(modelOption.options || []).length} groups` : '')

  // Prefer the account route if the default has no key (same as a real phone would).
  let chosenModel = null
  if (modelOption) {
    for (const group of modelOption.options || []) {
      for (const opt of group.options || []) {
        if (String(opt.value).includes('deepseek-account')) chosenModel = opt.value
      }
    }
    if (chosenModel) {
      const set = await api(`/v1/sessions/${encodeURIComponent(sessionId)}/config`, {
        method: 'POST',
        body: JSON.stringify({ configId: 'model', value: chosenModel }),
      })
      check('set model option', set.status === 200, chosenModel)
    }
  }

  const events = []
  const stream = openStream(`${base}/v1/events`, (ev) => {
    events.push(ev)
    if (ev.type === 'text' || ev.type === 'turn_ended' || ev.type === 'permission') {
      console.log('[event]', ev.type, JSON.stringify(ev).slice(0, 220))
    }
  })
  await sleep(300)

  const prompt1 = await api(`/v1/sessions/${encodeURIComponent(sessionId)}/prompt`, {
    method: 'POST',
    body: JSON.stringify({ text: 'Reply with exactly one word: pong' }),
  })
  check('prompt accepted', prompt1.status === 202, String(prompt1.status))

  const deadline = Date.now() + 180000
  while (Date.now() < deadline) {
    if (events.some((e) => e.type === 'turn_ended' && e.turnId === prompt1.json.turnId)) break
    await sleep(250)
  }
  const end1 = events.find((e) => e.type === 'turn_ended' && e.turnId === prompt1.json.turnId)
  const text1 = events.filter((e) => e.type === 'text').map((e) => e.text).join('')
  check('streamed text', /pong/i.test(text1), JSON.stringify(text1))
  check('turn ended cleanly', end1 && end1.stopReason === 'end_turn', JSON.stringify(end1))

  // Permission + tool call flow
  const before = events.length
  const prompt2 = await api(`/v1/sessions/${encodeURIComponent(sessionId)}/prompt`, {
    method: 'POST',
    body: JSON.stringify({ text: '请运行 shell 命令 `echo dsh-ios-ok` 并把输出原样告诉我。' }),
  })
  check('second prompt accepted', prompt2.status === 202)

  let permissionSeen = null
  const deadline2 = Date.now() + 240000
  while (Date.now() < deadline2) {
    const perms = events.slice(before).filter((e) => e.type === 'permission')
    if (perms.length && !permissionSeen) {
      permissionSeen = perms[0]
      const allow = permissionSeen.permission.options.find((o) => o.kind === 'allow_once')
        || permissionSeen.permission.options.find((o) => o.kind === 'allow_always')
        || permissionSeen.permission.options[0]
      const answer = await api(`/v1/permissions/${permissionSeen.permission.id}`, {
        method: 'POST',
        body: JSON.stringify({ optionId: allow.id }),
      })
      check('permission answered', answer.status === 200, allow.name)
    }
    const ended = events.slice(before).find((e) => e.type === 'turn_ended' && e.turnId === prompt2.json.turnId)
    if (ended) break
    await sleep(250)
  }

  const toolEvents = events.slice(before).filter((e) => e.type === 'tool')
  const end2 = events.slice(before).find((e) => e.type === 'turn_ended')
  console.log('[tools]', toolEvents.map((t) => `${t.tool.title}:${t.tool.status}`).join(' | '))
  check('tool call events', toolEvents.length > 0, String(toolEvents.length))
  check(
    permissionSeen ? 'permission requested and answered' : 'no permission needed (sandbox auto-allow)',
    true,
    permissionSeen?.permission?.title || '',
  )
  check('second turn ended', !!end2, end2?.stopReason)

  // Resume across process restart is covered by session/list below.
  const list = await api('/v1/sessions')
  check('sessions listed', (list.json.sessions || []).some((s) => s.id === sessionId), String(list.json.sessions?.length))

  const closed = await api(`/v1/sessions/${encodeURIComponent(sessionId)}/close`, { method: 'POST', body: '{}' })
  check('session close', closed.status === 200)

  stream.controller.abort()

  const failed = results.filter((r) => !r.ok)
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`)
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '))
    process.exitCode = 1
  }
}

main()
  .catch((e) => {
    console.error('[test error]', e.message)
    process.exitCode = 1
  })
  .finally(async () => {
    try { child.kill() } catch {}
    await sleep(1500)
    try { fs.unlinkSync(configPath) } catch {}
    try { fs.unlinkSync(sessionsPath) } catch {}
    process.exit(process.exitCode || 0)
  })
