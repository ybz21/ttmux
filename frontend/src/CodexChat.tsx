// Codex 对话面板 —— 读 codex rollout(JSONL) 渲染成对话，输入框经 ttmux send 注入。
// 相比 Claude 面板，这里对 codex 工具做了「特殊渲染」：
//   shell/exec_command → 终端命令卡片（$ cmd + 折叠输出）
//   apply_patch        → 彩色 diff 补丁
//   reasoning          → 折叠「推理」
import { useEffect, useRef, useState } from 'react'
import { Button, Input } from 'antd'
import { api } from './api'
import FileBrowser from './FileBrowser'
import Markdown from './Markdown'
import { PromptPanel } from './prompt'

interface Block { kind: string; text?: string; name?: string; input?: string; isError?: boolean }
interface Msg { role: string; blocks: Block[]; ts?: string }

const ACCENT = '#10a37f' // OpenAI 绿
const mono = 'ui-monospace, SFMono-Regular, Menlo, monospace'

// 从 function_call 入参里提取 shell 命令（cmd / command）
function extractCmd(input?: string): string | null {
  if (!input) return null
  try {
    const o = JSON.parse(input)
    return o.cmd || o.command || (Array.isArray(o.argv) ? o.argv.join(' ') : null)
  } catch { return null }
}

// 入参精简成一行摘要
function argSummary(input?: string): string {
  if (!input) return ''
  try {
    const o = JSON.parse(input)
    const key = ['path', 'file_path', 'pattern', 'query', 'cmd', 'command'].find((k) => o[k])
    const v = key ? String(o[key]) : JSON.stringify(o)
    return v.length > 140 ? v.slice(0, 140) + '…' : v
  } catch { return input.slice(0, 140) }
}

function Collapsible({ label, text, color, open: dflt = false }: { label: string; text?: string; color: string; open?: boolean }) {
  const [open, setOpen] = useState(dflt)
  if (!text) return null
  return (
    <div style={{ fontSize: 12 }}>
      <a onClick={() => setOpen((o) => !o)} style={{ color }}>{open ? '▾' : '▸'} {label}</a>
      {open && <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', margin: '4px 0 0', maxHeight: 320, overflow: 'auto', background: '#0d1117', padding: 8, borderRadius: 6, fontFamily: mono, color: '#c9d1d9' }}>{text}</pre>}
    </div>
  )
}

// 彩色 diff（apply_patch 的 input 即补丁文本）
function Patch({ text }: { text: string }) {
  return (
    <pre style={{ margin: 0, whiteSpace: 'pre-wrap', wordBreak: 'break-word', maxHeight: 360, overflow: 'auto', fontFamily: mono, fontSize: 12, lineHeight: 1.45 }}>
      {text.split('\n').map((l, i) => {
        let color = '#8b949e'
        if (l.startsWith('+') && !l.startsWith('+++')) color = '#3fb950'
        else if (l.startsWith('-') && !l.startsWith('---')) color = '#f85149'
        else if (l.startsWith('@@') || l.startsWith('***')) color = '#d2a8ff'
        else color = '#c9d1d9'
        return <div key={i} style={{ color }}>{l || ' '}</div>
      })}
    </pre>
  )
}

function ToolCard({ b }: { b: Block }) {
  // apply_patch：直接展示补丁 diff
  if (b.name === 'apply_patch') {
    return (
      <div style={{ border: '1px solid #30363d', borderRadius: 8, background: '#0d1117', padding: '8px 10px' }}>
        <div style={{ color: ACCENT, fontWeight: 600, fontSize: 12.5, marginBottom: 6 }}>✎ apply_patch</div>
        {b.input && <Patch text={b.input} />}
      </div>
    )
  }
  // shell / exec_command：终端命令卡片
  const cmd = extractCmd(b.input)
  if (cmd) {
    return (
      <div style={{ border: '1px solid #30363d', borderRadius: 8, background: '#0d1117', padding: '6px 10px', fontFamily: mono, fontSize: 12.5 }}>
        <span style={{ color: ACCENT }}>❯</span>{' '}
        <span style={{ color: '#c9d1d9', whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{cmd}</span>
      </div>
    )
  }
  // 其他工具：名称 + 一行摘要
  return (
    <div style={{ border: '1px solid #30363d', borderRadius: 8, background: '#0d1117', padding: '6px 10px', fontSize: 12.5 }}>
      <span style={{ color: ACCENT, fontWeight: 600 }}>⚙ {b.name}</span>
      {argSummary(b.input) && <span style={{ color: '#8b949e', marginLeft: 8, fontFamily: mono }}>{argSummary(b.input)}</span>}
    </div>
  )
}

function Bubble({ m }: { m: Msg }) {
  const isUser = m.role === 'user'
  const isTool = m.role === 'tool'
  const align = isUser ? 'flex-end' : 'flex-start'
  const bg = isUser ? ACCENT : isTool ? 'transparent' : '#161b22'
  const border = isUser ? 'none' : '1px solid #30363d'
  return (
    <div style={{ display: 'flex', justifyContent: align, margin: '6px 0' }}>
      <div style={{ maxWidth: isTool ? '100%' : '86%', width: isTool ? '100%' : 'auto', background: bg, border, borderRadius: 12, padding: isTool ? 0 : '8px 12px', color: isUser ? '#fff' : '#e6edf3', display: 'flex', flexDirection: 'column', gap: 6 }}>
        {m.blocks.map((b, i) => {
          if (b.kind === 'text') return <Markdown key={i} accent={isUser ? '#d6fff0' : ACCENT}>{b.text || ''}</Markdown>
          if (b.kind === 'thinking') return <Collapsible key={i} label="推理" text={b.text} color="#8b949e" />
          if (b.kind === 'tool_use') return <ToolCard key={i} b={b} />
          if (b.kind === 'tool_result') return <Collapsible key={i} label={b.isError ? '⚠ 输出（出错）' : '输出'} text={b.text} color={b.isError ? '#f85149' : '#8b949e'} />
          return null
        })}
      </div>
    </div>
  )
}

export default function CodexChat({ name, file, dir, onBack }: { name: string; file?: string; dir?: string; onBack: () => void }) {
  const [msgs, setMsgs] = useState<Msg[]>([])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [err, setErr] = useState('')
  const [showFiles, setShowFiles] = useState(false)
  const offsetRef = useRef(0)
  const fileRef = useRef<string | undefined>(file)
  const boxRef = useRef<HTMLDivElement>(null)
  const atBottom = useRef(true)

  useEffect(() => {
    let stop = false
    offsetRef.current = 0
    fileRef.current = file
    setMsgs([])
    const poll = async () => {
      try {
        const q = new URLSearchParams({ offset: String(offsetRef.current) })
        if (fileRef.current) q.set('file', fileRef.current)
        const r = await api('GET', `/sessions/${encodeURIComponent(name)}/codex-transcript?${q.toString()}`)
        const d = r.data
        if (stop) return
        if (d.file) fileRef.current = d.file
        if (d.messages?.length) { setMsgs((m) => [...m, ...d.messages]); offsetRef.current = d.nextOffset }
        else if (typeof d.nextOffset === 'number') offsetRef.current = d.nextOffset
      } catch (e: any) { if (!stop) setErr(e.message) }
    }
    poll()
    const t = setInterval(poll, 2000)
    return () => { stop = true; clearInterval(t) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name])

  useEffect(() => {
    if (atBottom.current && boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight
  }, [msgs])

  const onScroll = () => {
    const el = boxRef.current
    if (el) atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  }

  const send = async () => {
    const text = input.trim()
    if (!text || sending) return
    setSending(true); setErr('')
    try { await api('POST', '/tasks/_/send', { sess: name, msg: text }); setInput(''); atBottom.current = true }
    catch (e: any) { setErr(e.message) }
    finally { setSending(false) }
  }

  return (
    <div style={{ display: 'flex', height: '100%', background: '#06090d' }}>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px', borderBottom: '1px solid #30363d' }}>
          <span style={{ color: ACCENT, fontWeight: 600 }}>✸ Codex</span>
          <span style={{ color: '#8b949e', fontSize: 12 }}>{name}</span>
          <span style={{ flex: 1 }} />
          <Button size="small" type={showFiles ? 'primary' : 'default'}
            style={showFiles ? { background: ACCENT, borderColor: ACCENT } : {}}
            onClick={() => setShowFiles((s) => !s)}>📁 文件</Button>
          <Button size="small" onClick={onBack}>切回终端 ▸</Button>
        </div>
        <div ref={boxRef} onScroll={onScroll} style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 12px' }}>
          {msgs.length === 0 && <div style={{ color: '#8b949e', textAlign: 'center', marginTop: 30 }}>加载对话记录…</div>}
          {msgs.map((m, i) => <Bubble key={i} m={m} />)}
        </div>
        {/* 交互式选择框（审批/选项菜单）：检测到才显示，可点选 */}
        <PromptPanel name={name} accent={ACCENT} />
        {err && <div style={{ color: '#f85149', fontSize: 12, padding: '2px 12px' }}>{err}</div>}
        <div style={{ display: 'flex', gap: 8, padding: 10, borderTop: '1px solid #30363d' }}>
          <Input.TextArea
            value={input} onChange={(e) => setInput(e.target.value)}
            autoSize={{ minRows: 1, maxRows: 5 }} placeholder="给 Codex 发消息（Enter 发送，Shift+Enter 换行）"
            onPressEnter={(e) => { if (!e.shiftKey) { e.preventDefault(); send() } }}
          />
          <Button type="primary" loading={sending} onClick={send} style={{ background: ACCENT, borderColor: ACCENT }}>发送</Button>
        </div>
      </div>
      {showFiles && (
        <div style={{ flex: '0 0 clamp(200px, 32%, 300px)', minWidth: 0 }}>
          <FileBrowser dir={dir} accent={ACCENT} onClose={() => setShowFiles(false)} />
        </div>
      )}
    </div>
  )
}
