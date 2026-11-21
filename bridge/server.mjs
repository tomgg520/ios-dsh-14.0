#!/usr/bin/env node
/**
 * DSH iOS Bridge
 * --------------
 * Runs a small HTTP + Server-Sent-Events server on your computer and drives a
 * real DeepSeek Harness agent through the Agent Client Protocol (ACP) over
 * stdio. The iOS client talks only to this bridge.
 *
 *   iPhone (DSHClient.app)
 *        │  HTTP / SSE (LAN, bearer token)
 *        ▼
 *   this bridge  ──stdio JSON-RPC (ACP)──▶  dsh --profile acp
 *
 * No npm dependencies. Run it with Node 20+, or with the Node runtime that
 * ships inside the DeepSeek Harness Desktop app (see start-bridge.cmd).
 */

import http from 'node:http'
import os from 'node:os'
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { spawn } from 'node:child_process'
import { createInterface } from 'node:readline'
import { fileURLToPath } from 'node:url'

const BRIDGE_VERSION = '0.1.0'
const ACP_PROTOCOL_VERSION = 1
const HERE = path.dirname(fileURLToPath(import.meta.url))
const CONFIG_PATH = process.env.DSH_BRIDGE_CONFIG || path.join(HERE, 'config.json')
const SESSIONS_PATH = process.env.DSH_BRIDGE_SESSIONS || path.join(HERE, 'sessions.json')
const EVENT_BUFFER_SIZE = 800
const AUTH_FAILURE_LIMIT = 25

// ---------------------------------------------------------------------------
// tiny helpers
// ---------------------------------------------------------------------------

const nowIso = () => new Date().toISOString()
const log = (...args) => console.log(`[${new Date().toLocaleTimeString('en-GB')}]`, ...args)
const warn = (...args) => console.error(`[${new Date().toLocaleTimeString('en-GB')}]`, ...args)

class HttpError extends Error {
  constructor(status, code, message, details) {
    super(message)
    this.status = status
    this.code = code
    this.details = details
  }
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    return fallback
  }
}

function writeJson(file, value) {
  const tmp = `${file}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2), 'utf8')
  fs.renameSync(tmp, file)
}

function truncate(text, max) {
  const s = String(text ?? '')
  return s.length > max ? `${s.slice(0, max)}…` : s
}

function randomToken() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  const bytes = crypto.randomBytes(8)
  let out = ''
  for (let i = 0; i < 8; i += 1) out += alphabet[bytes[i] % alphabet.length]
  return `${out.slice(0, 4)}-${out.slice(4)}`
}

function lanAddresses() {
  const out = []
  const ifaces = os.networkInterfaces()
  for (const name of Object.keys(ifaces)) {
    for (const info of ifaces[name] || []) {
      if (info && info.family === 'IPv4' && !info.internal) {
        out.push({ iface: name, address: info.address })
      }
    }
  }
  return out
}

function expandHome(p) {
  if (!p) return p
  if (p === '~') return os.homedir()
  if (p.startsWith('~/') || p.startsWith('~\\')) return path.join(os.homedir(), p.slice(2))
  return p
}

// ---------------------------------------------------------------------------
// configuration
// ---------------------------------------------------------------------------

function defaultConfig() {
  return {
    port: 8787,
    host: '0.0.0.0',
    token: randomToken(),
    autoApprove: false,
    workspaces: [],
    defaultCwd: '',
    dsh: { command: [], env: {} },
  }
}

function detectDsh() {
  const candidates = []

  if (process.platform === 'win32') {
    const base = path.join(process.env.LOCALAPPDATA || '', 'Programs', 'DeepSeek Harness')
    candidates.push({
      label: 'DeepSeek Harness Desktop (Windows)',
      command: [
        path.join(base, 'DeepSeek Harness.exe'),
        path.join(base, 'resources', 'app.asar', 'dsh', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
        '--profile',
        'acp',
      ],
      env: { ELECTRON_RUN_AS_NODE: '1' },
      probe: path.join(base, 'resources', 'app.asar', 'dsh', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
    })
    candidates.push({
      label: 'DeepSeek Harness (Windows, user install)',
      command: [path.join(process.env.LOCALAPPDATA || '', 'Programs', 'dsh', 'dsh.exe'), '--profile', 'acp'],
      probe: path.join(process.env.LOCALAPPDATA || '', 'Programs', 'dsh', 'dsh.exe'),
    })
  }

  if (process.platform === 'darwin') {
    const app = '/Applications/DeepSeek Harness.app'
    candidates.push({
      label: 'DeepSeek Harness Desktop (macOS)',
      command: [
        path.join(app, 'Contents', 'MacOS', 'DeepSeek Harness'),
        path.join(app, 'Contents', 'Resources', 'app.asar', 'dsh', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
        '--profile',
        'acp',
      ],
      env: { ELECTRON_RUN_AS_NODE: '1' },
      probe: path.join(app, 'Contents', 'Resources', 'app.asar', 'dsh', 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
    })
    candidates.push({
      label: 'dsh on PATH',
      command: ['dsh', '--profile', 'acp'],
      probe: '/usr/local/bin/dsh',
    })
  }

  candidates.push({
    label: 'Node: npx @deepseek-ai/dsh',
    command: ['npx', '--yes', '@deepseek-ai/dsh', '--profile', 'acp'],
    env: {},
    probe: null,
  })

  for (const candidate of candidates) {
    if (!candidate.probe) continue
    try {
      if (fs.existsSync(candidate.probe)) return candidate
    } catch {
      // ignore
    }
  }

  // Last resort: assume `dsh` is on PATH.
  return { label: 'dsh on PATH', command: ['dsh', '--profile', 'acp'], env: {}, probe: null }
}

function loadConfig() {
  const defaults = defaultConfig()
  const stored = readJson(CONFIG_PATH, {})
  const config = { ...defaults, ...stored, dsh: { ...defaults.dsh, ...(stored.dsh || {}) } }
  if (!config.token || typeof config.token !== 'string') config.token = defaults.token
  if (!fs.existsSync(CONFIG_PATH)) writeJson(CONFIG_PATH, config)
  return config
}

// ---------------------------------------------------------------------------
// ACP host: owns the `dsh --profile acp` child process
// ---------------------------------------------------------------------------

class AcpHost {
  constructor({ command, env, cwd }) {
    this.command = command
    this.env = env
    this.cwd = cwd
    this.child = null
    this.state = 'stopped'
    this.agentInfo = null
    this.lastError = null
    this.stderrTail = []
    this.pending = new Map()
    this.nextId = 1
    this.readyPromise = null
    this.stopping = false
    this.restarts = 0
    this.listeners = new Map()
  }

  on(event, handler) {
    const list = this.listeners.get(event) || []
    list.push(handler)
    this.listeners.set(event, list)
    return this
  }

  emit(event, payload) {
    for (const handler of this.listeners.get(event) || []) {
      try {
        handler(payload)
      } catch (error) {
        warn('[acp] listener failed:', error)
      }
    }
  }

  setState(state, detail) {
    if (this.state === state) return
    this.state = state
    this.lastError = detail || null
    this.emit('state', { state, detail: detail || null })
  }

  ensure() {
    if (this.readyPromise) return this.readyPromise
    this.readyPromise = this.start().catch((error) => {
      this.readyPromise = null
      throw error
    })
    return this.readyPromise
  }

  async start() {
    if (this.child) return
    const [cmd, ...args] = this.command
    this.setState('starting')
    log(`[acp] starting: ${cmd} ${args.join(' ')}`)

    const child = spawn(cmd, args, {
      cwd: this.cwd,
      env: { ...process.env, ...this.env },
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    })
    this.child = child

    child.on('error', (error) => {
      this.failAll(error)
      this.setState('failed', `无法启动 dsh：${error.message}`)
    })

    child.on('exit', (code, signal) => {
      const wasReady = this.state === 'ready'
      this.child = null
      this.readyPromise = null
      this.failAll(new Error(`dsh 进程已退出（code=${code}, signal=${signal}）`))
      if (this.stopping) {
        this.setState('stopped', null)
        return
      }
      this.setState('stopped', `dsh 已退出（code=${code}）`)
      if (wasReady && this.restarts < 5) {
        this.restarts += 1
        const delay = Math.min(1000 * 2 ** (this.restarts - 1), 16000)
        log(`[acp] restarting in ${delay}ms (attempt ${this.restarts})`)
        setTimeout(() => {
          this.ensure().catch((error) => warn('[acp] restart failed:', error.message))
        }, delay)
      }
    })

    const rl = createInterface({ input: child.stdout })
    rl.on('line', (line) => this.handleLine(line))

    child.stderr.on('data', (chunk) => {
      const text = chunk.toString()
      this.stderrTail.push(text)
      if (this.stderrTail.length > 80) this.stderrTail.shift()
      for (const line of text.split(/\r?\n/)) {
        if (line.trim()) log('[dsh]', line.trim())
      }
    })

    const init = await this.request('initialize', {
      protocolVersion: ACP_PROTOCOL_VERSION,
      clientCapabilities: {
        fs: { readTextFile: false, writeTextFile: false },
        terminal: false,
      },
      clientInfo: { name: 'dsh-ios-bridge', version: BRIDGE_VERSION },
    }, 60000)

    this.agentInfo = init.agentInfo || null
    this.setState('ready')
    this.restarts = 0
    log('[acp] ready:', JSON.stringify(this.agentInfo))
  }

  handleLine(line) {
    if (!line.trim()) return
    let msg
    try {
      msg = JSON.parse(line)
    } catch {
      log('[acp] non-JSON stdout:', truncate(line, 300))
      return
    }

    if (msg.id !== undefined && msg.method === undefined) {
      const pending = this.pending.get(msg.id)
      if (!pending) return
      this.pending.delete(msg.id)
      if (pending.timer) clearTimeout(pending.timer)
      if (msg.error) pending.reject(new Error(msg.error.message || JSON.stringify(msg.error)))
      else pending.resolve(msg.result)
      return
    }

    if (msg.method && msg.id !== undefined) {
      this.emit('request', msg)
      return
    }

    if (msg.method) {
      if (msg.method === 'session/update') this.emit('update', msg.params)
      else this.emit('notification', msg)
    }
  }

  request(method, params, timeoutMs = 60000) {
    if (!this.child) return Promise.reject(new Error('dsh 未运行'))
    const id = this.nextId++
    return new Promise((resolve, reject) => {
      const timer = timeoutMs > 0
        ? setTimeout(() => {
            this.pending.delete(id)
            reject(new Error(`ACP 请求超时：${method}`))
          }, timeoutMs)
        : null
      this.pending.set(id, { resolve, reject, timer })
      this.write({ jsonrpc: '2.0', id, method, params })
    })
  }

  notify(method, params) {
    this.write({ jsonrpc: '2.0', method, params })
  }

  respond(id, result) {
    this.write({ jsonrpc: '2.0', id, result })
  }

  write(message) {
    if (!this.child || !this.child.stdin.writable) return false
    try {
      this.child.stdin.write(`${JSON.stringify(message)}\n`)
      return true
    } catch (error) {
      warn('[acp] write failed:', error.message)
      return false
    }
  }

  failAll(error) {
    for (const [, pending] of this.pending) {
      if (pending.timer) clearTimeout(pending.timer)
      pending.reject(error)
    }
    this.pending.clear()
  }

  async stop() {
    this.stopping = true
    const child = this.child
    this.child = null
    if (!child) return
    try {
      child.stdin.end()
    } catch {
      // ignore
    }
    await new Promise((resolve) => {
      const timer = setTimeout(() => {
        try {
          child.kill('SIGKILL')
        } catch {
          // ignore
        }
        resolve()
      }, 2000)
      child.once('exit', () => {
        clearTimeout(timer)
        resolve()
      })
    })
  }
}

// ---------------------------------------------------------------------------
// Bridge: HTTP API + SSE fan-out + session bookkeeping
// ---------------------------------------------------------------------------

class Bridge {
  constructor(config) {
    this.config = config
    this.sessions = new Map() // sessionId -> { id, cwd, title, updatedAt }
    this.liveSessions = new Set()
    this.configCache = new Map() // sessionId -> configOptions
    this.activeTurns = new Map() // sessionId -> { turnId, startedAt }
    this.permissions = new Map() // permissionId -> { resolve, sessionId, toolCall, timer }
    this.permissionSeq = 0
    this.clients = new Set()
    this.buffer = []
    this.eventSeq = 0
    this.authFailures = new Map()
    this.dsh = null
    this.lanUrls = []

    this.restoreSessions()
  }

  // -- persistence ---------------------------------------------------------

  restoreSessions() {
    const stored = readJson(SESSIONS_PATH, { sessions: [] })
    for (const item of stored.sessions || []) {
      if (item && typeof item.id === 'string') this.sessions.set(item.id, item)
    }
  }

  persistSessions() {
    try {
      writeJson(SESSIONS_PATH, { sessions: [...this.sessions.values()] })
    } catch (error) {
      warn('[bridge] failed to persist sessions:', error.message)
    }
  }

  rememberSession(id, patch) {
    const current = this.sessions.get(id) || { id, cwd: '', title: '新会话', updatedAt: nowIso() }
    const next = { ...current, ...patch, updatedAt: nowIso() }
    this.sessions.set(id, next)
    this.persistSessions()
    return next
  }

  // -- ACP wiring ----------------------------------------------------------

  startDsh() {
    const override = this.config.dsh?.command
    const detected = detectDsh()
    const command = Array.isArray(override) && override.length ? override : detected.command
    const env = { ...(detected.env || {}), ...(this.config.dsh?.env || {}) }

    this.dsh = new AcpHost({ command, env, cwd: os.homedir() })
    log(`[bridge] dsh backend: ${detected.label} → ${command.join(' ')}`)

    this.dsh.on('state', ({ state, detail }) => {
      this.broadcast({ type: 'state', dsh: state, detail })
      if (state !== 'ready') this.liveSessions.clear()
    })

    this.dsh.on('update', (params) => this.onSessionUpdate(params))

    this.dsh.on('request', (msg) => {
      if (msg.method === 'session/request_permission') {
        this.onPermissionRequest(msg)
        return
      }
      if (msg.method === 'session/update') return
      this.dsh.respond(msg.id, {})
    })

    this.dsh.ensure().catch((error) => {
      warn('[bridge] dsh failed to start:', error.message)
      this.dsh.setState('failed', error.message)
    })
  }

  async ensureDsh() {
    if (!this.dsh) throw new HttpError(503, 'dsh-unavailable', 'dsh 后端尚未初始化')
    await this.dsh.ensure()
  }

  onSessionUpdate(params) {
    const sessionId = params?.sessionId
    const update = params?.update
    if (!sessionId || !update) return

    switch (update.sessionUpdate) {
      case 'user_message_chunk':
        return
      case 'agent_message_chunk': {
        const text = textOf(update.content)
        if (text) this.broadcast({ type: 'text', sessionId, messageId: update.messageId || null, text })
        return
      }
      case 'agent_thought_chunk': {
        const text = textOf(update.content)
        if (text) this.broadcast({ type: 'thought', sessionId, messageId: update.messageId || null, text })
        return
      }
      case 'tool_call': {
        this.broadcast({
          type: 'tool',
          sessionId,
          tool: {
            id: update.toolCallId,
            title: update.title || '工具调用',
            kind: update.kind || 'other',
            status: update.status || 'pending',
            detail: toolDetail(update),
          },
        })
        return
      }
      case 'tool_call_update': {
        this.broadcast({
          type: 'tool',
          sessionId,
          tool: {
            id: update.toolCallId,
            title: update.title || null,
            kind: update.kind || null,
            status: update.status || null,
            detail: toolDetail(update),
          },
        })
        return
      }
      case 'plan': {
        const entries = (update.entries || []).map((entry) => ({
          content: entry.content,
          status: entry.status,
          priority: entry.priority || null,
        }))
        this.broadcast({ type: 'plan', sessionId, entries })
        return
      }
      case 'usage_update':
        this.broadcast({ type: 'usage', sessionId, used: update.used, size: update.size })
        return
      case 'config_option_update':
        this.configCache.set(sessionId, update.configOptions || [])
        this.broadcast({ type: 'config', sessionId, config: update.configOptions || [] })
        return
      case 'session_info_update':
        if (update.title) {
          this.rememberSession(sessionId, { title: update.title })
          this.broadcast({ type: 'title', sessionId, title: update.title })
        }
        return
      default:
        this.broadcast({ type: 'info', sessionId, update: update.sessionUpdate })
    }
  }

  onPermissionRequest(msg) {
    const { sessionId, toolCall, options } = msg.params || {}
    const choices = options || []
    const permissionId = `perm_${++this.permissionSeq}`

    const allow = choices.find((o) => o.kind === 'allow_once') || choices.find((o) => o.kind === 'allow_always') || null

    if (this.config.autoApprove && allow) {
      this.dsh.respond(msg.id, { outcome: { outcome: 'selected', optionId: allow.optionId } })
      this.broadcast({
        type: 'permission_resolved',
        sessionId,
        permissionId,
        optionId: allow.optionId,
        auto: true,
      })
      return
    }

    const timer = setTimeout(() => {
      if (!this.permissions.has(permissionId)) return
      this.permissions.delete(permissionId)
      this.dsh.respond(msg.id, { outcome: { outcome: 'cancelled' } })
      this.broadcast({ type: 'permission_resolved', sessionId, permissionId, optionId: null, timeout: true })
    }, 5 * 60 * 1000)

    this.permissions.set(permissionId, {
      resolve: (optionId) => {
        clearTimeout(timer)
        if (optionId) this.dsh.respond(msg.id, { outcome: { outcome: 'selected', optionId } })
        else this.dsh.respond(msg.id, { outcome: { outcome: 'cancelled' } })
      },
      sessionId,
      timer,
    })

    this.broadcast({
      type: 'permission',
      sessionId,
      permission: {
        id: permissionId,
        title: toolCall?.title || '需要授权',
        detail: toolDetail(toolCall || {}),
        options: choices.map((o) => ({ id: o.optionId, name: o.name, kind: o.kind })),
      },
    })
  }

  // -- SSE ----------------------------------------------------------------

  broadcast(payload) {
    const event = { ...payload, id: ++this.eventSeq, ts: nowIso() }
    this.buffer.push(event)
    if (this.buffer.length > EVENT_BUFFER_SIZE) this.buffer.splice(0, this.buffer.length - EVENT_BUFFER_SIZE)
    const frame = `id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`
    for (const res of this.clients) {
      try {
        res.write(frame)
      } catch {
        this.clients.delete(res)
      }
    }
  }

  // -- API ----------------------------------------------------------------

  async health() {
    return {
      ok: true,
      bridge: BRIDGE_VERSION,
      time: nowIso(),
      dsh: {
        state: this.dsh?.state || 'stopped',
        agent: this.dsh?.agentInfo || null,
        error: this.dsh?.lastError || null,
      },
      sessions: this.sessions.size,
    }
  }

  workspaces() {
    const seen = new Set()
    const out = []
    const add = (name, rawPath) => {
      const p = expandHome(rawPath)
      if (!p) return
      const abs = path.resolve(p)
      if (seen.has(abs)) return
      seen.add(abs)
      out.push({ name: name || path.basename(abs) || abs, path: abs })
    }

    for (const item of this.config.workspaces || []) {
      if (typeof item === 'string') add(path.basename(item), item)
      else if (item && item.path) add(item.name, item.path)
    }

    if (out.length === 0) {
      add('主目录', os.homedir())
      const desktop = path.join(os.homedir(), 'Desktop')
      const documents = path.join(os.homedir(), 'Documents')
      if (fs.existsSync(desktop)) add('桌面', desktop)
      if (fs.existsSync(documents)) add('文稿', documents)
      add('当前目录', process.cwd())
    }

    return out
  }

  async listSessions() {
    const merged = new Map()
    for (const session of this.sessions.values()) {
      merged.set(session.id, { ...session, live: this.liveSessions.has(session.id) })
    }

    if (this.dsh?.state === 'ready') {
      try {
        const result = await this.dsh.request('session/list', {}, 15000)
        for (const info of result?.sessions || []) {
          // 只补充桥接服务自己创建的会话，避免列出无法续接的其它客户端会话。
          const existing = merged.get(info.sessionId)
          if (!existing) continue
          merged.set(info.sessionId, {
            ...existing,
            cwd: existing.cwd || info.cwd || '',
            title: info.title || existing.title || '新会话',
            updatedAt: info.updatedAt || existing.updatedAt,
            live: this.liveSessions.has(info.sessionId),
          })
        }
      } catch (error) {
        log('[bridge] session/list failed:', error.message)
      }
    }

    return [...merged.values()].sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))
  }

  async createSession({ cwd, title }) {
    await this.ensureDsh()
    const workspace = path.resolve(expandHome(cwd || this.config.defaultCwd || this.workspaces()[0].path))
    const result = await this.dsh.request('session/new', { cwd: workspace, mcpServers: [] }, 60000)
    const session = this.rememberSession(result.sessionId, {
      cwd: workspace,
      title: title || '新会话',
      updatedAt: nowIso(),
    })
    this.liveSessions.add(result.sessionId)
    this.configCache.set(result.sessionId, result.configOptions || [])
    this.broadcast({ type: 'session_created', session })
    return { session, config: result.configOptions || [] }
  }

  async ensureLive(sessionId) {
    if (this.liveSessions.has(sessionId)) return
    const meta = this.sessions.get(sessionId)
    if (!meta) throw new HttpError(404, 'session-not-found', '本机没有这个会话')
    const result = await this.dsh.request('session/resume', { sessionId, cwd: meta.cwd }, 60000)
    this.liveSessions.add(sessionId)
    if (result?.configOptions) {
      this.configCache.set(sessionId, result.configOptions)
      this.broadcast({ type: 'config', sessionId, config: result.configOptions })
    }
  }

  async resumeSession(sessionId) {
    await this.ensureDsh()
    await this.ensureLive(sessionId)
    return this.configCache.get(sessionId) || []
  }

  async prompt(sessionId, text) {
    if (!text || !String(text).trim()) throw new HttpError(400, 'empty-prompt', '消息不能为空')
    if (this.activeTurns.has(sessionId)) throw new HttpError(409, 'busy', '该会话正在回复中')

    await this.ensureDsh()
    await this.ensureLive(sessionId)

    const meta = this.sessions.get(sessionId)
    const isFirstTurn = !meta || meta.title === '新会话'
    const turnId = crypto.randomUUID()
    this.activeTurns.set(sessionId, { turnId, startedAt: Date.now() })
    this.broadcast({ type: 'turn_started', sessionId, turnId })

    if (isFirstTurn) {
      const title = truncate(String(text).replace(/\s+/g, ' ').trim(), 36)
      this.rememberSession(sessionId, { title })
      this.broadcast({ type: 'title', sessionId, title })
    }

    const promise = this.dsh.request('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text: String(text) }],
    }, 0)

    promise
      .then((result) => {
        this.broadcast({
          type: 'turn_ended',
          sessionId,
          turnId,
          stopReason: result?.stopReason || 'end_turn',
          error: null,
        })
      })
      .catch((error) => {
        this.broadcast({
          type: 'turn_ended',
          sessionId,
          turnId,
          stopReason: 'error',
          error: error.message,
        })
      })
      .finally(() => {
        this.activeTurns.delete(sessionId)
        this.rememberSession(sessionId, {})
      })

    return { turnId }
  }

  async cancel(sessionId) {
    await this.ensureDsh()
    if (!this.activeTurns.has(sessionId)) return { cancelled: false }
    this.dsh.notify('session/cancel', { sessionId })
    return { cancelled: true }
  }

  async setConfig(sessionId, configId, value) {
    await this.ensureDsh()
    await this.ensureLive(sessionId)
    const result = await this.dsh.request('session/set_config_option', {
      sessionId,
      configId,
      value,
    }, 30000)
    if (result?.configOptions) {
      this.configCache.set(sessionId, result.configOptions)
      this.broadcast({ type: 'config', sessionId, config: result.configOptions })
    }
    return { config: result?.configOptions || [] }
  }

  async closeSession(sessionId) {
    await this.ensureDsh()
    try {
      await this.dsh.request('session/close', { sessionId }, 30000)
    } catch (error) {
      log('[bridge] session/close failed:', error.message)
    }
    this.liveSessions.delete(sessionId)
    this.activeTurns.delete(sessionId)
    return { closed: true }
  }

  resolvePermission(permissionId, optionId) {
    const pending = this.permissions.get(permissionId)
    if (!pending) throw new HttpError(404, 'permission-not-found', '该授权请求已失效')
    this.permissions.delete(permissionId)
    pending.resolve(optionId || null)
    this.broadcast({
      type: 'permission_resolved',
      sessionId: pending.sessionId,
      permissionId,
      optionId: optionId || null,
    })
    return { resolved: true }
  }
}

function textOf(content) {
  if (!content) return ''
  if (content.type === 'text') return content.text || ''
  if (content.type === 'resource_link') return `[${content.name || content.uri}]`
  return ''
}

function toolDetail(toolCall) {
  const parts = []
  if (toolCall.content && Array.isArray(toolCall.content)) {
    for (const block of toolCall.content) {
      if (block.type === 'content' && block.content?.type === 'text') parts.push(block.content.text)
      else if (block.type === 'diff') parts.push(`${block.path || '文件'}\n${block.newText || ''}`)
    }
  }
  if (!parts.length && toolCall.rawInput !== undefined && toolCall.rawInput !== null) {
    try {
      parts.push(typeof toolCall.rawInput === 'string' ? toolCall.rawInput : JSON.stringify(toolCall.rawInput, null, 2))
    } catch {
      // ignore
    }
  }
  if (!parts.length && toolCall.rawOutput !== undefined && toolCall.rawOutput !== null) {
    try {
      parts.push(typeof toolCall.rawOutput === 'string' ? toolCall.rawOutput : JSON.stringify(toolCall.rawOutput, null, 2))
    } catch {
      // ignore
    }
  }
  return truncate(parts.join('\n\n'), 4000)
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

async function readBody(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > 1024 * 1024) throw new HttpError(413, 'body-too-large', '请求体过大')
    chunks.push(chunk)
  }
  if (!chunks.length) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    throw new HttpError(400, 'bad-json', '请求体不是合法 JSON')
  }
}

function createServer(bridge) {
  const config = bridge.config
  const tokenHash = crypto.createHash('sha256').update(String(config.token)).digest()

  function authorized(req, url) {
    const header = req.headers.authorization || ''
    const bearer = header.startsWith('Bearer ') ? header.slice(7) : ''
    const query = url.searchParams.get('token') || ''
    const provided = bearer || query
    if (!provided) return false
    const hash = crypto.createHash('sha256').update(String(provided)).digest()
    return crypto.timingSafeEqual(hash, tokenHash)
  }

  function guard(req, res, url) {
    if (authorized(req, url)) return true
    const ip = req.socket.remoteAddress || 'unknown'
    const failures = (bridge.authFailures.get(ip) || 0) + 1
    bridge.authFailures.set(ip, failures)
    setTimeout(() => bridge.authFailures.delete(ip), 60000)
    if (failures > AUTH_FAILURE_LIMIT) {
      sendJson(res, 429, { ok: false, error: { code: 'too-many-requests', message: '尝试次数过多，请稍后再试' } })
      return false
    }
    sendJson(res, 401, { ok: false, error: { code: 'unauthorized', message: '配对码不正确' } })
    return false
  }

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`)

    res.setHeader('Access-Control-Allow-Origin', '*')
    res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type, Last-Event-ID')
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    if (req.method === 'OPTIONS') {
      res.writeHead(204)
      res.end()
      return
    }

    if (url.pathname === '/' || url.pathname === '/v1') {
      sendJson(res, 200, {
        ok: true,
        name: 'dsh-ios-bridge',
        version: BRIDGE_VERSION,
        docs: 'https://github.com/deepseek-ai/deepseek-harness',
      })
      return
    }

    if (url.pathname === '/v1/health') {
      if (!guard(req, res, url)) return
      sendJson(res, 200, await bridge.health())
      return
    }

    if (!url.pathname.startsWith('/v1/')) {
      sendJson(res, 404, { ok: false, error: { code: 'not-found', message: '未知路径' } })
      return
    }

    if (!guard(req, res, url)) return

    try {
      await route(req, res, url, bridge)
    } catch (error) {
      if (error instanceof HttpError) {
        sendJson(res, error.status, { ok: false, error: { code: error.code, message: error.message, details: error.details } })
      } else {
        warn('[bridge] request failed:', error)
        sendJson(res, 500, { ok: false, error: { code: 'internal', message: error.message || '内部错误' } })
      }
    }
  })

  server.on('clientError', (error, socket) => {
    if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\n\r\n')
  })

  return server
}

async function route(req, res, url, bridge) {
  const parts = url.pathname.split('/').filter(Boolean) // ['v1', ...]
  const method = req.method || 'GET'

  // GET /v1/server
  if (method === 'GET' && parts.length === 2 && parts[1] === 'server') {
    sendJson(res, 200, {
      ok: true,
      name: os.hostname(),
      platform: process.platform,
      bridge: BRIDGE_VERSION,
      dsh: { state: bridge.dsh?.state || 'stopped', agent: bridge.dsh?.agentInfo || null, error: bridge.dsh?.lastError || null },
      workspaces: bridge.workspaces(),
      urls: bridge.lanUrls,
      autoApprove: Boolean(bridge.config.autoApprove),
    })
    return
  }

  // GET /v1/workspaces
  if (method === 'GET' && parts.length === 2 && parts[1] === 'workspaces') {
    sendJson(res, 200, { ok: true, workspaces: bridge.workspaces() })
    return
  }

  // GET /v1/events (SSE)
  if (method === 'GET' && parts.length === 2 && parts[1] === 'events') {
    openEvents(req, res, bridge)
    return
  }

  // /v1/sessions
  if (parts.length === 2 && parts[1] === 'sessions') {
    if (method === 'GET') {
      sendJson(res, 200, { ok: true, sessions: await bridge.listSessions() })
      return
    }
    if (method === 'POST') {
      const body = await readBody(req)
      const created = await bridge.createSession({ cwd: body.cwd, title: body.title })
      sendJson(res, 200, { ok: true, ...created })
      return
    }
  }

  // /v1/sessions/:id/<action>
  if (parts.length >= 4 && parts[1] === 'sessions') {
    const sessionId = decodeURIComponent(parts[2])
    const action = parts[3]

    if (method === 'POST' && action === 'prompt') {
      const body = await readBody(req)
      sendJson(res, 202, { ok: true, ...(await bridge.prompt(sessionId, body.text)) })
      return
    }
    if (method === 'POST' && action === 'cancel') {
      sendJson(res, 200, { ok: true, ...(await bridge.cancel(sessionId)) })
      return
    }
    if (method === 'POST' && action === 'close') {
      sendJson(res, 200, { ok: true, ...(await bridge.closeSession(sessionId)) })
      return
    }
    if (method === 'POST' && action === 'config') {
      const body = await readBody(req)
      sendJson(res, 200, {
        ok: true,
        ...(await bridge.setConfig(sessionId, body.configId, body.value)),
      })
      return
    }
    if (method === 'POST' && action === 'resume') {
      const config = await bridge.resumeSession(sessionId)
      sendJson(res, 200, { ok: true, config })
      return
    }
  }

  // /v1/permissions/:id
  if (method === 'POST' && parts.length === 3 && parts[1] === 'permissions') {
    const body = await readBody(req)
    sendJson(res, 200, { ok: true, ...bridge.resolvePermission(decodeURIComponent(parts[2]), body.optionId || null) })
    return
  }

  throw new HttpError(404, 'not-found', `未知接口：${method} ${url.pathname}`)
}

function openEvents(req, res, bridge) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
    'Access-Control-Allow-Origin': '*',
  })
  if (res.socket) res.socket.setNoDelay(true)

  res.write('retry: 2000\n\n')
  res.write(`event: hello\ndata: ${JSON.stringify({
    type: 'hello',
    id: 0,
    ts: nowIso(),
    bridge: BRIDGE_VERSION,
    dsh: bridge.dsh?.state || 'stopped',
    agent: bridge.dsh?.agentInfo || null,
  })}\n\n`)

  if (bridge.dsh) {
    res.write(`event: state\ndata: ${JSON.stringify({
      type: 'state',
      id: 0,
      ts: nowIso(),
      dsh: bridge.dsh.state,
      detail: bridge.dsh.lastError,
    })}\n\n`)
  }

  const lastId = Number(req.headers['last-event-id'] || 0)
  if (Number.isFinite(lastId) && lastId > 0) {
    for (const event of bridge.buffer) {
      if (event.id > lastId) {
        res.write(`id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`)
      }
    }
  }

  bridge.clients.add(res)

  const heartbeat = setInterval(() => {
    try {
      res.write(`: ping ${Date.now()}\n\n`)
    } catch {
      // ignore
    }
  }, 15000)

  const cleanup = () => {
    clearInterval(heartbeat)
    bridge.clients.delete(res)
  }
  req.on('close', cleanup)
  req.on('error', cleanup)
}

function sendJson(res, status, payload) {
  if (res.writableEnded) return
  const body = JSON.stringify(payload)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  })
  res.end(body)
}

// ---------------------------------------------------------------------------
// boot
// ---------------------------------------------------------------------------

async function main() {
  const config = loadConfig()
  const bridge = new Bridge(config)

  bridge.lanUrls = [
    `http://127.0.0.1:${config.port}`,
    ...lanAddresses().map((item) => `http://${item.address}:${config.port}`),
  ]

  const server = createServer(bridge)
  server.keepAliveTimeout = 65000
  server.headersTimeout = 66000

  const listen = (port) => new Promise((resolve, reject) => {
    const onError = (error) => {
      server.removeListener('listening', onListening)
      reject(error)
    }
    const onListening = () => {
      server.removeListener('error', onError)
      resolve()
    }
    server.once('error', onError)
    server.once('listening', onListening)
    server.listen(port, config.host)
  })

  let port = Number(config.port) || 8787
  for (let attempt = 0; attempt < 10; attempt += 1) {
    try {
      await listen(port)
      break
    } catch (error) {
      if (error.code !== 'EADDRINUSE' || attempt === 9) {
        warn(`[bridge] 无法监听 ${config.host}:${port}：${error.message}`)
        warn('[bridge] 请修改 config.json 中的 port，或关闭占用该端口的程序。')
        process.exit(1)
      }
      log(`[bridge] 端口 ${port} 被占用，尝试 ${port + 1}…`)
      port += 1
    }
  }

  if (port !== config.port) {
    config.port = port
    writeJson(CONFIG_PATH, config)
  }

  bridge.lanUrls = [
    `http://127.0.0.1:${port}`,
    ...lanAddresses().map((item) => `http://${item.address}:${port}`),
  ]

  const lan = lanAddresses()
  const line = '─'.repeat(58)
  console.log(`\n${line}`)
  console.log('  DSH iOS 桥接服务已启动')
  console.log(line)
  console.log(`  配对地址   http://${lan[0]?.address || '127.0.0.1'}:${port}`)
  if (lan.length > 1) {
    for (const item of lan.slice(1)) console.log(`             http://${item.address}:${port}`)
  }
  console.log(`  配对码     ${config.token}`)
  console.log(`  工作目录   ${bridge.workspaces().map((w) => w.path).join(', ')}`)
  console.log(`  自动授权   ${config.autoApprove ? '开（工具调用无需在手机上确认）' : '关（工具调用需要在手机上确认）'}`)
  console.log(line)
  console.log('  在 iPhone 客户端里填入上面的“配对地址”和“配对码”。')
  console.log('  Windows 首次运行如弹出防火墙提示，请允许“专用网络”。')
  console.log(`${line}\n`)

  bridge.startDsh()

  let shuttingDown = false
  const shutdown = async (signal) => {
    if (shuttingDown) return
    shuttingDown = true
    console.log(`\n[bridge] 收到 ${signal}，正在关闭…`)
    for (const client of bridge.clients) {
      try {
        client.end()
      } catch {
        // ignore
      }
    }
    server.close()
    if (bridge.dsh) await bridge.dsh.stop()
    bridge.persistSessions()
    process.exit(0)
  }
  process.on('SIGINT', () => shutdown('SIGINT'))
  process.on('SIGTERM', () => shutdown('SIGTERM'))
  process.on('uncaughtException', (error) => warn('[bridge] uncaught exception:', error))
  process.on('unhandledRejection', (error) => warn('[bridge] unhandled rejection:', error))
}

main().catch((error) => {
  warn('[bridge] fatal:', error)
  process.exit(1)
})
