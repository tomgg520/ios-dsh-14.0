// A scripted ACP agent used to test the bridge's permission/cancel plumbing
// without spending model tokens. Speaks newline-delimited JSON-RPC on stdio.
import { createInterface } from 'node:readline'

let nextId = 5000
const pendingPrompts = new Map() // permission request id -> prompt request message
const waitingCancel = new Map() // sessionId -> prompt id

function send(message) {
  process.stdout.write(JSON.stringify(message) + '\n')
}

function result(id, value) {
  send({ jsonrpc: '2.0', id, result: value })
}

function update(sessionId, value) {
  send({ jsonrpc: '2.0', method: 'session/update', params: { sessionId, update: value } })
}

createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return
  let msg
  try {
    msg = JSON.parse(line)
  } catch {
    return
  }

  // Client's answer to our permission request
  if (msg.id !== undefined && msg.method === undefined) {
    const prompt = pendingPrompts.get(msg.id)
    if (!prompt) return
    pendingPrompts.delete(msg.id)
    const outcome = msg.result?.outcome
    if (outcome?.outcome !== 'selected' || outcome.optionId !== 'allow') {
      result(prompt.id, { stopReason: 'refusal' })
      return
    }
    update(prompt.params.sessionId, {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'tool-1',
      status: 'completed',
      content: [{ type: 'content', content: { type: 'text', text: 'dsh-ios-ok' } }],
    })
    result(prompt.id, { stopReason: 'end_turn' })
    return
  }

  switch (msg.method) {
    case 'initialize':
      result(msg.id, {
        protocolVersion: 1,
        agentInfo: { name: 'fake-acp', version: '0.0.1' },
        agentCapabilities: { promptCapabilities: {}, sessionCapabilities: { close: {}, list: {}, resume: {} } },
        authMethods: [],
      })
      return
    case 'session/new':
      result(msg.id, {
        sessionId: 'fake-session',
        configOptions: [
          {
            id: 'model',
            name: 'Model',
            type: 'select',
            currentValue: 'fake-model',
            options: [{ value: 'fake-model', name: 'Fake Model' }],
          },
        ],
      })
      return
    case 'session/resume':
    case 'session/close':
      result(msg.id, {})
      return
    case 'session/list':
      result(msg.id, {
        sessions: [{ sessionId: 'fake-session', cwd: process.cwd(), title: 'Fake', updatedAt: new Date().toISOString() }],
      })
      return
    case 'session/set_config_option':
      result(msg.id, {
        configOptions: [
          { id: 'model', name: 'Model', type: 'select', currentValue: msg.params.value, options: [{ value: 'fake-model', name: 'Fake Model' }] },
        ],
      })
      return
    case 'session/prompt': {
      const sessionId = msg.params.sessionId
      const text = (msg.params.prompt || []).map((b) => b.text || '').join(' ')
      update(sessionId, {
        sessionUpdate: 'agent_thought_chunk',
        content: { type: 'text', text: '正在处理…' },
      })
      if (text.includes('cancel')) {
        waitingCancel.set(sessionId, msg.id)
        return
      }
      const permissionId = nextId++
      pendingPrompts.set(permissionId, msg)
      send({
        jsonrpc: '2.0',
        id: permissionId,
        method: 'session/request_permission',
        params: {
          sessionId,
          toolCall: {
            toolCallId: 'tool-1',
            title: '运行命令 echo dsh-ios-ok',
            kind: 'execute',
            status: 'pending',
            rawInput: { command: 'echo dsh-ios-ok' },
          },
          options: [
            { optionId: 'allow', name: '允许', kind: 'allow_once' },
            { optionId: 'deny', name: '拒绝', kind: 'reject_once' },
          ],
        },
      })
      return
    }
    case 'session/cancel': {
      const sessionId = msg.params.sessionId
      const promptId = waitingCancel.get(sessionId)
      if (promptId !== undefined) {
        waitingCancel.delete(sessionId)
        result(promptId, { stopReason: 'cancelled' })
      }
      return
    }
    default:
      if (msg.id !== undefined) result(msg.id, {})
  }
})

process.stdin.on('end', () => process.exit(0))
