// Verifies the bridge's permission round-trip, cancel path and auth with a
// scripted ACP agent (no model tokens spent).
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'))
const bridgePath = path.join(here, '..', 'bridge', 'server.mjs')
const fakePath = path.join(here, 'fake-acp.mjs')
const configPath = path.join(os.tmpdir(), `dsh-bridge-proto-${Date.now()}.json`)
const sessionsPath = path.join(os.tmpdir(), `dsh-bridge-proto-sessions-${Date.now()}.json`)
const port = 19000 + Math.floor(Math.random() * 800)
const token = 'PROTO-CODE'

fs.writeFileSync(configPath, JSON.stringify({
  port,
  host: '127.0.0.1',
  token,
  autoApprove: false,
  workspaces: [process.cwd()],
  defaultCwd: process.cwd(),
  dsh: {
    command: [process.execPath, fakePath],
    env: { ELECTRON_RUN_AS_NODE: '1' },
  },
}, null, 2))

const base = `http://127.0.0.1:${port}`
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const checks = []
const check = (name, ok, extra) => { checks.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  ' + extra : ''}`) }

const child = spawn(process.execPath, [bridgePath], {
  cwd: process.cwd(),
  env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', DSH_BRIDGE_CONFIG: configPath, DSH_BRIDGE_SESSIONS: sessionsPath },
  stdio: ['ignore', 'pipe', 'pipe'],
  windowsHide: true,
})
child.stdout.on('data', (d) => process.stdout.write('[bridge] ' + d))
child.stderr.on('data', (d) => process.stdout.write('[bridge:err] ' + d))

const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }
async function api(p, options = {}) {
  const res = await fetch(base + p, { ...options, headers: { ...headers, ...(options.headers || {}) } })
  const text = await res.text()
  let json
  try { json = JSON.parse(text) } catch { json = { raw: text } }
  return { status: res.status, json }
}

async function waitReady() {
  for (let i = 0; i < 60; i++) {
    try {
      const { json } = await api('/v1/server')
      if (json?.dsh?.state === 'ready') return
    } catch {}
    await sleep(500)
  }
  throw new Error('bridge not ready')
}

function stream(url, onEvent) {
  const controller = new AbortController()
  const task = (async () => {
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
  })().catch((e) => { if (e.name !== 'AbortError') console.error(e.message) })
  return { controller, task }
}

const main = async () => {
  await waitReady()
  const health = await api('/v1/health')
  check('health ok', health.status === 200 && health.json.ok)

  const unauthorized = await fetch(base + '/v1/health')
  check('rejects missing token', unauthorized.status === 401)

  const created = await api('/v1/sessions', { method: 'POST', body: JSON.stringify({}) })
  check('session created', created.status === 200 && created.json.session.id === 'fake-session')

  const resumed = await api('/v1/sessions/fake-session/resume', { method: 'POST', body: '{}' })
  check('resume returns cached config', Array.isArray(resumed.json.config) && resumed.json.config.length === 1,
    JSON.stringify(resumed.json.config || []).slice(0, 80))

  const events = []
  const s = stream(`${base}/v1/events`, (ev) => events.push(ev))
  await sleep(300)

  const p1 = await api('/v1/sessions/fake-session/prompt', { method: 'POST', body: JSON.stringify({ text: '跑个命令' }) })
  check('prompt accepted', p1.status === 202)

  let permission = null
  for (let i = 0; i < 80 && !permission; i++) {
    permission = events.find((e) => e.type === 'permission' && e.sessionId === 'fake-session')
    if (!permission) await sleep(100)
  }
  check('permission event reached client', !!permission, permission?.permission?.title)
  check('permission carries options', (permission?.permission?.options || []).length === 2)

  const answered = await api(`/v1/permissions/${permission.permission.id}`, { method: 'POST', body: JSON.stringify({ optionId: 'allow' }) })
  check('permission answer accepted', answered.status === 200)

  for (let i = 0; i < 80; i++) {
    if (events.some((e) => e.type === 'turn_ended' && e.turnId === p1.json.turnId)) break
    await sleep(100)
  }
  const end1 = events.find((e) => e.type === 'turn_ended' && e.turnId === p1.json.turnId)
  check('turn ends after permission', end1?.stopReason === 'end_turn', JSON.stringify(end1?.stopReason))
  const toolDone = events.filter((e) => e.type === 'tool' && e.tool.status === 'completed')
  check('tool completion streamed', toolDone.length === 1, toolDone[0]?.tool.detail)

  // cancel path
  const before = events.length
  const p2 = await api('/v1/sessions/fake-session/prompt', { method: 'POST', body: JSON.stringify({ text: 'please cancel' }) })
  check('second prompt accepted', p2.status === 202)
  await sleep(400)
  const cancelled = await api('/v1/sessions/fake-session/cancel', { method: 'POST', body: '{}' })
  check('cancel accepted', cancelled.json.cancelled === true)
  for (let i = 0; i < 80; i++) {
    if (events.slice(before).some((e) => e.type === 'turn_ended')) break
    await sleep(100)
  }
  const end2 = events.slice(before).find((e) => e.type === 'turn_ended')
  check('cancelled turn reported', end2?.stopReason === 'cancelled', JSON.stringify(end2?.stopReason))

  const denied = await api('/v1/sessions/nope/prompt', { method: 'POST', body: JSON.stringify({ text: 'hi' }) })
  check('unknown session -> 404', denied.status === 404, String(denied.status))

  s.controller.abort()
  const failed = checks.filter((c) => !c.ok)
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`)
  if (failed.length) process.exitCode = 1
}

main()
  .catch((e) => { console.error('[test error]', e.message); process.exitCode = 1 })
  .finally(async () => {
    try { child.kill() } catch {}
    await sleep(1200)
    try { fs.unlinkSync(configPath) } catch {}
    try { fs.unlinkSync(sessionsPath) } catch {}
    process.exit(process.exitCode || 0)
  })
