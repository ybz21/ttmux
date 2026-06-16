// Claude Code 对话面板 —— 读会话的 JSONL 记录渲染成对话气泡，输入框经 ttmux send 注入。
// 渲染风格参考 sugyan/claude-code-webui：user 右、assistant 左、thinking 折叠、工具调用卡片。
import { useEffect, useRef, useState } from 'react'
import { Button, Input } from 'antd'
import { api } from './api'
import FileBrowser from './FileBrowser'
import Markdown from './Markdown'
import { PromptPanel } from './prompt'

interface Block { kind: string; text?: string; name?: string; input?: string; isError?: boolean }
interface Msg { role: string; blocks: Block[]; ts?: string }

// 工具入参精简成一行摘要（command / file_path / pattern 等优先）
function toolSummary(input?: string): string {
  if (!input) return ''
  try {
    const o = JSON.parse(input)
    const key = ['command', 'file_path', 'path', 'pattern', 'query', 'prompt', 'description'].find((k) => o[k])
    const v = key ? String(o[key]) : JSON.stringify(o)
    return v.length > 120 ? v.slice(0, 120) + '…' : v
  } catch { return input.slice(0, 120) }
}

function ToolUse({ b }: { b: Block }) {
  return (
    <div style={{ border: '1px solid #30363d', borderRadius: 8, background: '#0d1117', padding: '6px 10px', fontSize: 12.5 }}>
      <span style={{ color: '#d2a8ff', fontWeight: 600 }}>⚙ {b.name}</span>
      {toolSummary(b.input) && <span style={{ color: '#8b949e', marginLeft: 8, fontFamily: 'ui-monospace, monospace' }}>{toolSummary(b.input)}</span>}
    </div>
  )
}

function Collapsible({ label, text, color, mono }: { label: string; text?: string; color: string; mono?: boolean }) {
  const [open, setOpen] = useState(false)
  if (!text) return null
  return (
    <div style={{ fontSize: 12 }}>
      <a onClick={() => setOpen((o) => !o)} style={{ color }}>{open ? '▾' : '▸'} {label}</a>
      {open && <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', margin: '4px 0 0', maxHeight: 320, overflow: 'auto', background: '#0d1117', padding: 8, borderRadius: 6, fontFamily: mono ? 'ui-monospace, monospace' : 'inherit', color: '#c9d1d9' }}>{text}</pre>}
    </div>
  )
}

function Bubble({ m }: { m: Msg }) {
  const isUser = m.role === 'user'
  const isTool = m.role === 'tool'
  const align = isUser ? 'flex-end' : 'flex-start'
  const bg = isUser ? '#1f6feb' : isTool ? 'transparent' : '#161b22'
  const border = isUser ? 'none' : '1px solid #30363d'
  const maxW = isTool ? '100%' : '86%'
  return (
    <div style={{ display: 'flex', justifyContent: align, margin: '6px 0' }}>
      <div style={{ maxWidth: maxW, width: isTool ? '100%' : 'auto', background: bg, border, borderRadius: 12, padding: isTool ? 0 : '8px 12px', color: isUser ? '#fff' : '#e6edf3', display: 'flex', flexDirection: 'column', gap: 6 }}>
        {m.blocks.map((b, i) => {
          if (b.kind === 'text') return <Markdown key={i} accent={isUser ? '#cfe1ff' : '#58a6ff'}>{b.text || ''}</Markdown>
          if (b.kind === 'thinking') return <Collapsible key={i} label="思考过程" text={b.text} color="#8b949e" />
          if (b.kind === 'tool_use') return <ToolUse key={i} b={b} />
          if (b.kind === 'tool_result') return <Collapsible key={i} label={b.isError ? '⚠ 工具输出（错误）' : '工具输出'} text={b.text} color={b.isError ? '#f85149' : '#8b949e'} mono />
          return null
        })}
      </div>
    </div>
  )
}

export default function ClaudeChat({ name, file, dir, onBack }: { name: string; file?: string; dir?: string; onBack: () => void }) {
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
        const r = await api('GET', `/sessions/${encodeURIComponent(name)}/transcript?${q.toString()}`)
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
        {/* 头 */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px', borderBottom: '1px solid #30363d' }}>
          <span style={{ color: '#d2a8ff', fontWeight: 600 }}>🤖 Claude Code</span>
          <span style={{ color: '#8b949e', fontSize: 12 }}>{name}</span>
          <span style={{ flex: 1 }} />
          <Button size="small" type={showFiles ? 'primary' : 'default'} onClick={() => setShowFiles((s) => !s)}>📁 文件</Button>
          <Button size="small" onClick={onBack}>切回终端 ▸</Button>
        </div>
        {/* 对话 */}
        <div ref={boxRef} onScroll={onScroll} style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 12px' }}>
          {msgs.length === 0 && <div style={{ color: '#8b949e', textAlign: 'center', marginTop: 30 }}>加载对话记录…</div>}
          {msgs.map((m, i) => <Bubble key={i} m={m} />)}
        </div>
        {/* 交互式选择框（权限确认/选项菜单）：检测到才显示，可点选 */}
        <PromptPanel name={name} accent="#d2a8ff" />
        {/* 输入 */}
        {err && <div style={{ color: '#f85149', fontSize: 12, padding: '2px 12px' }}>{err}</div>}
        <div style={{ display: 'flex', gap: 8, padding: 10, borderTop: '1px solid #30363d' }}>
          <Input.TextArea
            value={input} onChange={(e) => setInput(e.target.value)}
            autoSize={{ minRows: 1, maxRows: 5 }} placeholder="给 Claude 发消息（Enter 发送，Shift+Enter 换行）"
            onPressEnter={(e) => { if (!e.shiftKey) { e.preventDefault(); send() } }}
          />
          <Button type="primary" loading={sending} onClick={send}>发送</Button>
        </div>
      </div>
      {showFiles && (
        <div style={{ flex: '0 0 clamp(200px, 32%, 300px)', minWidth: 0 }}>
          <FileBrowser dir={dir} accent="#d2a8ff" onClose={() => setShowFiles(false)} />
        </div>
      )}
    </div>
  )
}
