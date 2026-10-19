window.__ModuleLoader__.load({
  id: 'dsh-appshots',
  factory: (require) => {
    const module = { exports: {} }
    const exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })
    const React = require('react')

    const inject = ['slots', 'sessions', 'conversation']
    const RECENT_DEFAULT_MS = 60_000
    const PREVIEW_STORE_KEY = 'dsh-appshots-preview-v1'
    const PREVIEW_STORE_LIMIT = 40

    function readPreviewStore() {
      try {
        const raw = window.localStorage.getItem(PREVIEW_STORE_KEY)
        const parsed = raw ? JSON.parse(raw) : null
        return parsed && typeof parsed === 'object' ? parsed : {}
      } catch {
        return {}
      }
    }

    function writePreviewStore(store) {
      try { window.localStorage.setItem(PREVIEW_STORE_KEY, JSON.stringify(store)) } catch {}
    }

    function persistPreviewRecord(record) {
      const store = readPreviewStore()
      const keys = [record.name, record.title].filter(Boolean)
      for (const key of keys) store[key] = record
      const names = Object.keys(store)
      if (names.length > PREVIEW_STORE_LIMIT) {
        for (const key of names.slice(0, names.length - PREVIEW_STORE_LIMIT)) delete store[key]
      }
      writePreviewStore(store)
    }

    function storedPreviewForAlt(alt) {
      const store = readPreviewStore()
      const name = String(alt || '').trim()
      if (!name) return null
      const stem = name.replace(/^appshot-/, '').replace(/\.png$/i, '')
      return store[name] || store[stem] || null
    }
    const CSS = `
.dsh-appshots-btn{
  appearance:none;border:0;background:transparent;color:var(--dsw-alias-label-secondary);
  width:32px;height:32px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;
}
.dsh-appshots-btn:hover{background:var(--dsw-alias-interactive-bg-hover);color:var(--dsw-alias-label-primary)}
.dsh-appshots-btn[data-busy="true"]{opacity:.55;cursor:progress}
.dsh-appshots-btn svg{width:18px;height:18px}
.dsh-appshots-notice{
  box-sizing:border-box;
  width:100%;
  max-width:var(--dsh-composer-card-max-width);
  margin:0 auto 6px;
  padding:4px 8px;
  background:var(--dsw-alias-interactive-bg-hover);
  color:var(--dsw-alias-label-secondary);
  border-radius:8px;
  font-size:12px;
  line-height:18px;
}
.dsh-appshots-notice-wrap{
  box-sizing:border-box;
  width:100%;
  padding:0 var(--dsh-composer-side-clearance);
  display:flex;
  flex-direction:column;
  align-items:center;
}
.dsh-appshots-notice-item{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dsh-appshots-lb-host{position:fixed;inset:0;z-index:1001;pointer-events:none}
.dsh-appshots-lb-tools{
  position:fixed;top:20px;right:68px;z-index:2;pointer-events:auto;
  display:flex;align-items:center;
}
.dsh-appshots-lb-textbtn{
  appearance:none;box-sizing:border-box;
  display:inline-flex;align-items:center;justify-content:center;
  height:36px;padding:0 14px;border-radius:999px;cursor:pointer;white-space:nowrap;
  border:1px solid var(--dsw-alias-border-l2-darkmode-thin);
  background:var(--dsw-specific-input-major);color:var(--dsw-alias-label-primary);
  font:var(--dsw-font-xs-13);
  font-family:var(--dsw-font-family);
}
.dsh-appshots-lb-textbtn:hover{background:var(--dsw-specific-input-major)}
.dsh-appshots-lb-textbtn[data-active="true"]{
  color:var(--dsw-alias-label-primary);
  background:var(--dsw-alias-button-ghost-active-fill);
  border-color:transparent;
  box-shadow:inset 0 0 0 1px var(--dsw-alias-button-ghost-active-border);
}
.dsh-appshots-lb-textbtn:focus-visible{outline:2px solid var(--dsw-alias-label-primary);outline-offset:2px}
.dsh-appshots-lb-card{
  position:fixed;z-index:1;pointer-events:auto;box-sizing:border-box;overflow:auto;
  border-radius:12px;padding:20px 24px 24px;
  background:var(--dsw-specific-input-major);color:var(--dsw-alias-label-primary);
  box-shadow:var(--dsw-shadow-lv3);overscroll-behavior:contain;
}
.dsh-appshots-lb-meta{
  margin:0 0 12px;
  font:var(--dsw-font-xxs-12);
  color:var(--dsw-alias-label-secondary);
}
.dsh-appshots-lb-body{
  margin:0;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word;user-select:text;
  font:var(--dsw-font-markdown-code-block);
  font-family:var(--ds-font-family-code, ui-monospace, SFMono-Regular, Menlo, monospace);
  color:var(--dsw-alias-label-primary);
}
`

    function errorMessage(error) {
      return error instanceof Error ? error.message : String(error)
    }

    function reportClient(level, message, error) {
      try {
        void fetch('/api/appshots/client-log', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ level, message, stack: error instanceof Error ? error.stack : undefined }),
        }).catch(() => {})
      } catch {}
    }

    const COMPACT_TEXT_LIMIT = 8000
    const COMPACT_ROLES = [
      'standard window', 'HTML content', 'scroll area', 'content list',
      'close button', 'minimize button', 'full screen button', 'zoom button',
      'toggle button', 'pop up button', 'text field', 'text entry area',
      'combo box', 'check box', 'radio button', 'menu bar', 'menu item',
      'progress indicator', 'button', 'link', 'tab', 'row', 'heading',
      'text', 'image', 'slider', 'list', 'table', 'cell', 'separator',
      'split group', 'tab group', 'container', 'group', 'splitter', 'toolbar', 'menu', 'outline',
    ].sort((a, b) => b.length - a.length)
    const COMPACT_DROP = new Set([
      'container', 'scroll area', 'content list', 'outline', 'group',
      'splitter', 'toolbar', 'menu bar', 'menu', 'menu item', 'row',
      'list', 'table', 'cell', 'separator', 'split group',
    ])
    const COMPACT_CHROME = new Set(['close button', 'minimize button', 'full screen button', 'zoom button'])
    const COMPACT_NAV_RE = /(^|[^a-z])(sidebar|navigation|nav)([^a-z]|$)|侧边栏|导航/iu
    const COMPACT_NAV_ROLES = new Set(['', 'container', 'group', 'split group', 'outline', 'list', 'content list', 'toolbar', '外框'])
    const COMPACT_INLINE = new Map([
      ['button', '[button]'],
      ['link', '[link]'],
      ['tab', '[tab]'],
      ['text field', '[text field]'],
      ['text entry area', '[text field]'],
      ['combo box', '[combo box]'],
      ['check box', '[check box]'],
      ['radio button', '[radio]'],
      ['image', '[image]'],
    ])

    function splitCompactRole(line) {
      const body = line.replace(/^\t+/u, '').trim()
      for (const role of COMPACT_ROLES) {
        if (body === role || body.startsWith(role + ' ')) {
          return { role, label: body.slice(role.length).trim() }
        }
      }
      return { role: '', label: body }
    }

    function compactLabel(label, keepUrl = false, forText = false) {
      let value = String(label || '')
      if (forText) {
        const bare = value.match(/^(?:text|heading),\s*Description:\s*([\s\S]*)$/u)
        if (bare) {
          value = bare[1]
        } else {
          const descriptionAt = value.search(/,\s*Description:\s*/u)
          if (descriptionAt > 10) value = value.slice(0, descriptionAt)
        }
      }
      value = value.replace(/,\s*Help:.*$/u, '').replace(/,\s*Value:.*$/u, '').trim()
      if (!keepUrl) value = value.replace(/,\s*URL:.*$/u, '').trim()
      return value
    }

    function compactLongText(text) {
      return String(text || '')
        .replace(/^ID:\s*[^,]+,\s*/u, '')
        .replace(/^Description:\s*/u, '')
        .replace(/\*\*/gu, '')
        .replace(/\s+###\s+/gu, '\n')
        .replace(/\s+\*\s+/gu, '\n')
        .trim()
    }

    function compactAppshotText(raw, limit = COMPACT_TEXT_LIMIT) {
      const out = []
      let paragraph = []
      let last = ''
      const flush = () => {
        if (paragraph.length === 0) return
        const text = paragraph.join(' ').replace(/\s+/gu, ' ').trim()
        paragraph = []
        if (text && text !== last) {
          out.push(text)
          last = text
        }
      }
      const push = (line) => {
        if (line && line !== last) {
          out.push(line)
          last = line
        }
      }
      let skipDepth = -1
      for (const line of String(raw || '').split('\n')) {
        if (!line.trim()) continue
        const depth = (line.match(/^\t*/u)?.[0].length ?? 0)
        if (skipDepth >= 0) {
          if (depth > skipDepth) continue
          skipDepth = -1
        }
        const { role, label } = splitCompactRole(line)
        if (role === 'toolbar' || role === 'tab group' || (COMPACT_NAV_ROLES.has(role) && COMPACT_NAV_RE.test(label))) {
          skipDepth = depth
          flush()
          continue
        }
        if (!role) {
          if (/^(The focused UI element is|scroll bar|value indicator)/u.test(label)) continue
          if (label) {
            flush()
            push(label)
          }
          continue
        }
        if (COMPACT_DROP.has(role) || COMPACT_CHROME.has(role)) {
          flush()
          continue
        }
        if (role === 'text') {
          const text = compactLabel(label, false, true)
          if (!text) continue
          if (text.length <= 30 || /^\d{1,2}:\d{2}$/u.test(text)) {
            flush()
            push(text)
          } else {
            paragraph.push(text)
          }
          continue
        }
        flush()
        if (role === 'standard window') {
          push(`standard window ${compactLabel(label)}`.trim())
          continue
        }
        const value = compactLabel(label, role === 'HTML content', role === 'heading')
        if (role === 'heading') {
          if (value) push(value)
          continue
        }
        if (COMPACT_INLINE.has(role)) {
          if (value && value.length > 120 && (role === 'button' || role === 'link')) {
            paragraph.push(compactLongText(value))
            continue
          }
          push(value ? `${COMPACT_INLINE.get(role)} ${value}` : COMPACT_INLINE.get(role))
          continue
        }
        push(value ? `${role} ${value}` : role)
      }
      flush()
      const lines = out
      let text = lines.join('\n')
      if (text.length > limit) {
        const budget = Math.max(1, limit - 40)
        const kept = []
        let size = 0
        for (let index = lines.length - 1; index >= 0; index -= 1) {
          const line = lines[index]
          if (size + line.length + 1 > budget) break
          kept.unshift(line)
          size += line.length + 1
        }
        if (kept.length === 0) {
          const lastLine = lines[lines.length - 1] || ''
          let piece = lastLine.slice(-budget)
          const boundary = piece.search(/[。！？；.!?;\s]/u)
          if (boundary > 0 && boundary < 300) piece = piece.slice(boundary + 1)
          kept.push(piece)
        }
        const header = lines[0]?.startsWith('standard window') ? `${lines[0]}\n` : ''
        text = `${header}…（已省略较早内容）\n${kept.join('\n')}`
      }
      return text.trim() || '此窗口没有可用的辅助功能文本。'
    }

    async function responseJson(response) {
      if (response.status === 204) return { ok: true }
      const body = await response.json().catch(() => ({}))
      if (!response.ok || body.ok === false) throw new Error(body.error || `HTTP ${response.status}`)
      return body
    }

    function base64ToFile(data, name, mediaType) {
      const binary = atob(data)
      const bytes = new Uint8Array(binary.length)
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
      return new File([bytes], name || 'appshot.png', { type: mediaType || 'image/png' })
    }

    function sleep(ms) {
      return new Promise((resolve) => setTimeout(resolve, ms))
    }

    function CameraIcon() {
      return React.createElement('svg', { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: '1.8' },
        React.createElement('path', { d: 'M4 8.5A2.5 2.5 0 0 1 6.5 6h1.2l.7-1.3A1.5 1.5 0 0 1 9.7 4h4.6a1.5 1.5 0 0 1 1.3.7L16.3 6h1.2A2.5 2.5 0 0 1 20 8.5v8A2.5 2.5 0 0 1 17.5 19h-11A2.5 2.5 0 0 1 4 16.5v-8Z' }),
        React.createElement('circle', { cx: '12', cy: '12.5', r: '3.2' }),
      )
    }

    class AppshotController {
      constructor(ctx) {
        this.ctx = ctx
        this.busy = false
        this.lastAttachAt = 0
        this.lastSessionId = undefined
        this.recentWindowMs = RECENT_DEFAULT_MS
        this.seen = new Set()
        this.listeners = new Set()
        this.disposeSource = undefined
        this.labelsByImageId = new Map()
        this.previewByImageId = new Map()
        this.previewByName = new Map()
        this.statusReported = false
        this.lastSent = undefined
      }

      rememberPreview(imageIds, pending) {
        const owner = String(pending.owner || '').trim() || '窗口'
        const title = String(pending.title || '').trim()
        const record = {
          owner,
          title,
          text: String(pending.text || ''),
          textTruncated: Boolean(pending.textTruncated),
          name: pending.name || `appshot-${owner}.png`,
        }
        for (const imageId of imageIds) this.previewByImageId.set(imageId, record)
        this.previewByName.set(record.name, record)
        if (title) this.previewByName.set(title, record)
        persistPreviewRecord(record)
      }

      previewForAlt(alt) {
        const name = String(alt || '').trim()
        if (!name) return null
        const stem = name.replace(/^appshot-/, '').replace(/\.png$/i, '')
        return this.previewByName.get(name)
          || this.previewByName.get(stem)
          || storedPreviewForAlt(name)
          || storedPreviewForAlt(stem)
          || null
      }

      formatPreview(record) {
        const title = record.title || 'Untitled'
        const owner = record.owner || 'Unknown'
        const body = compactAppshotText(record.text)
        const truncated = record.textTruncated ? '\n（原始辅助功能文本已截断）' : ''
        return {
          meta: `Window: "${title}", App: ${owner}.`,
          body: `${body}${truncated}`,
        }
      }

      subscribe(listener) {
        this.listeners.add(listener)
        return () => this.listeners.delete(listener)
      }

      publish() {
        for (const listener of this.listeners) listener()
      }

      async waitForShell(sessionId) {
        const started = Date.now()
        while (Date.now() - started < 4000) {
          try {
            return this.ctx.conversation.input.shell(sessionId)
          } catch {
            await sleep(40)
          }
        }
        throw new Error('会话输入框尚未就绪')
      }

      resolveTargetSessionId() {
        let uiSession
        try { uiSession = this.ctx.uiSession ?? this.ctx.get?.('uiSession') } catch {}
        const uiCurrent = uiSession?.current?.value?.key
        if (uiCurrent) return uiCurrent
        const state = this.ctx.sessions.list.getSnapshot()
        const current = state.current
        if (current) return current
        const retained = Object.entries(state.byId || {}).find(([, row]) => (
          Number(row?.retainedBy?.mainView ?? 0) > 0
        ))
        if (retained) return retained[0]
        if (Array.isArray(state.ids) && state.ids.length > 0) return state.ids[0]
        const now = Date.now()
        if (this.lastAttachAt && this.lastSessionId && now - this.lastAttachAt < this.recentWindowMs) {
          return this.lastSessionId
        }
        return undefined
      }

      async resolveSession() {
        const sessions = this.ctx.sessions
        const target = this.resolveTargetSessionId()
        if (target) {
          if (typeof sessions.open === 'function') {
            try { sessions.open(target) } catch {}
          }
          this.lastSessionId = target
          reportClient('info', `resolve session current=${target}`)
          return target
        }
        const created = await sessions.create({})
        if (typeof sessions.open === 'function') {
          try { sessions.open(created) } catch {}
        }
        this.lastSessionId = created
        reportClient('info', `resolve session created=${created}`)
        return created
      }

      attachDrafts(sessionId, shell, file) {
        const conversation = this.ctx.conversation
        const drafts = typeof conversation.createDrafts === 'function'
          ? conversation.createDrafts(sessionId, [file])
          : conversation.createDraftImages([file])
        const ids = drafts.map((draft) => draft.id)
        const added = typeof shell.addAttachments === 'function'
          ? shell.addAttachments(ids)
          : shell.addImages(ids)
        if (!added) {
          if (typeof conversation.releaseDraftAttachments === 'function') conversation.releaseDraftAttachments(drafts)
          else conversation.releaseDraftImages(drafts)
          throw new Error('当前输入框正忙，无法附加 Appshot')
        }
        return ids
      }

      async attachPending(id) {
        if (this.seen.has(id)) return
        this.seen.add(id)
        const run = async () => {
          try {
            const pending = await responseJson(await fetch(`/api/appshots/pending/${encodeURIComponent(id)}`))
            const data = String(pending.data || '')
            const signature = `${pending.owner || ''}\u0000${pending.title || ''}\u0000${data.length}\u0000${data.slice(0, 4096)}\u0000${data.slice(-4096)}`
            const now = Date.now()
            if (this.lastSent && this.lastSent.signature === signature && now - this.lastSent.at < 5000) {
              reportClient('info', `dedupe ${id}`)
              await fetch(`/api/appshots/pending/${encodeURIComponent(id)}`, { method: 'DELETE' }).catch(() => {})
              return
            }
            const sessionId = await this.resolveSession()
            const shell = await this.waitForShell(sessionId)
            const file = base64ToFile(pending.data, pending.name, pending.mediaType)
            const imageIds = this.attachDrafts(sessionId, shell, file)
            const rawText = String(pending.text || '').trim()
            if (rawText) {
              let textBinding = false
              try {
                const capabilities = await responseJson(await fetch('/api/appshots/capabilities'))
                textBinding = capabilities.textBinding === true
              } catch {}
              if (textBinding) {
                try {
                  await fetch('/api/appshots/bind', {
                    method: 'POST',
                    headers: { 'content-type': 'application/json' },
                    body: JSON.stringify({ sessionId, id: pending.id, text: compactAppshotText(rawText) }),
                  })
                } catch (error) {
                  reportClient('warn', `bind text failed for ${id}`, error)
                }
              }
            }
            const owner = String(pending.owner || '').trim() || '窗口'
            const title = String(pending.title || '').trim()
            const label = title && title !== owner ? `${owner} — ${title}` : owner
            for (const imageId of imageIds) this.labelsByImageId.set(imageId, label)
            this.rememberPreview(imageIds, pending)
            this.publish()
            this.lastAttachAt = Date.now()
            this.lastSessionId = sessionId
            this.lastSent = { signature, at: Date.now() }
            reportClient('info', `attached ${id}`)
            await fetch(`/api/appshots/pending/${encodeURIComponent(id)}`, { method: 'DELETE' }).catch(() => {})
          } catch (error) {
            this.seen.delete(id)
            reportClient('error', `attach failed for ${id}`, error)
            throw error
          }
        }
        this.attaching = (this.attaching || Promise.resolve()).then(run, run)
        return this.attaching
      }

      async captureFromUi() {
        if (this.busy) return
        this.busy = true
        this.publish()
        try {
          const captured = await responseJson(await fetch('/api/appshots/capture', {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: '{}',
          }))
          await this.attachPending(captured.id)
        } catch (error) {
          const current = this.ctx.sessions.list.getSnapshot().current
          if (current) {
            try { this.ctx.conversation.input.shell(current).notify('error', errorMessage(error)) } catch { console.error('[dsh-appshots]', error) }
          }
          console.error('[dsh-appshots]', error)
          throw error
        } finally {
          this.busy = false
          this.publish()
        }
      }

      async consumeLatest() {
        try {
          const listed = await responseJson(await fetch('/api/appshots/pending'))
          const items = Array.isArray(listed.items) ? listed.items : []
          for (const item of items) {
            if (item?.id) await this.attachPending(item.id)
          }
        } catch {
          try {
            const latest = await responseJson(await fetch('/api/appshots/latest'))
            if (latest?.id) await this.attachPending(latest.id)
          } catch {}
        }
      }

      start() {
        reportClient('info', 'client start')
        void this.refreshStatus()
        let source
        try {
          source = new EventSource('/api/appshots/events')
          source.onmessage = (event) => {
            let payload
            try { payload = JSON.parse(event.data) } catch { return }
            if (payload?.type === 'captured' && payload.id) {
              void this.attachPending(payload.id).catch((error) => {
                console.error('[dsh-appshots]', error)
              })
            }
          }
          source.onerror = () => {
            reportClient('warn', 'appshots SSE error; polling continues')
          }
        } catch (error) {
          reportClient('warn', 'EventSource unavailable; polling only', error)
          source = undefined
        }
        const poll = window.setInterval(() => { void this.consumeLatest() }, 900)
        this.disposeSource = () => {
          try { source?.close() } catch {}
          window.clearInterval(poll)
        }
        void this.consumeLatest()
        return () => {
          this.disposeSource?.()
        }
      }

      async refreshStatus() {
        try {
          const status = await responseJson(await fetch('/api/appshots/status'))
          if (typeof status.recentWindowMs === 'number') this.recentWindowMs = status.recentWindowMs
          if (!this.statusReported) {
            this.statusReported = true
            reportClient('info', `status hotkey=${status.hotkeyMode} attachText=${status.attachText}`)
          }
        } catch (error) {
          if (!this.statusReported) {
            this.statusReported = true
            reportClient('error', 'status failed', error)
          }
        }
      }
    }

    function mountLightboxOverlay(controller) {
      const host = document.createElement('div')
      host.dataset.plugin = 'dsh-appshots-lightbox'
      host.className = 'dsh-appshots-lb-host'
      document.body.appendChild(host)
      let open = false
      let record = null
      let imageEl = null
      let tools = null
      let button = null
      let card = null
      let metaEl = null
      let bodyEl = null

      const hideImage = (hidden) => {
        if (imageEl) imageEl.style.visibility = hidden ? 'hidden' : ''
      }

      const setImage = (next) => {
        if (imageEl && imageEl !== next) imageEl.style.visibility = ''
        imageEl = next
      }

      const ensureTools = () => {
        if (tools) return
        tools = document.createElement('div')
        tools.className = 'dsh-appshots-lb-tools'
        button = document.createElement('button')
        button.type = 'button'
        button.className = 'dsh-appshots-lb-textbtn'
        button.addEventListener('click', (event) => {
          event.preventDefault()
          event.stopPropagation()
          open = !open
          render()
        })
        tools.appendChild(button)
        host.appendChild(tools)
      }

      const ensureCard = () => {
        if (card) return
        card = document.createElement('div')
        card.className = 'dsh-appshots-lb-card'
        card.addEventListener('mousedown', (event) => event.stopPropagation())
        metaEl = document.createElement('p')
        metaEl.className = 'dsh-appshots-lb-meta'
        bodyEl = document.createElement('pre')
        bodyEl.className = 'dsh-appshots-lb-body'
        card.append(metaEl, bodyEl)
        host.appendChild(card)
      }

      const render = () => {
        if (!record) {
          hideImage(false)
          host.replaceChildren()
          tools = button = card = metaEl = bodyEl = null
          return
        }
        ensureTools()
        button.dataset.active = open ? 'true' : 'false'
        button.setAttribute('aria-pressed', open ? 'true' : 'false')
        button.textContent = open ? '查看图片' : '查看文本'
        if (!open || !imageEl) {
          hideImage(false)
          if (card) card.remove()
          card = metaEl = bodyEl = null
          return
        }
        ensureCard()
        const rect = imageEl.getBoundingClientRect()
        card.style.top = `${Math.round(rect.top)}px`
        card.style.left = `${Math.round(rect.left)}px`
        card.style.width = `${Math.max(1, Math.round(rect.width))}px`
        card.style.height = `${Math.max(1, Math.round(rect.height))}px`
        const preview = controller.formatPreview(record)
        if (metaEl.textContent !== preview.meta) metaEl.textContent = preview.meta
        if (bodyEl.textContent !== preview.body) bodyEl.textContent = preview.body
        hideImage(true)
      }

      const scan = () => {
        const dialogs = [...document.querySelectorAll('[role="dialog"][aria-modal="true"]')]
        const img = dialogs.map((dialog) => dialog.querySelector('img')).find(Boolean)
        const next = img ? controller.previewForAlt(img.getAttribute('alt') || '') : null
        if (!img) open = false
        setImage(img || null)
        record = next
        render()
      }

      const observer = new MutationObserver((mutations) => {
        if (mutations.every((mutation) => host.contains(mutation.target))) return
        scan()
      })
      observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['alt', 'src'] })
      window.addEventListener('resize', scan)
      const unsubscribe = controller.subscribe(scan)
      scan()
      return () => {
        hideImage(false)
        observer.disconnect()
        window.removeEventListener('resize', scan)
        unsubscribe()
        host.remove()
      }
    }

    function AppshotNotice({ controller, useInput }) {
      const [, setTick] = React.useState(0)
      React.useEffect(() => controller.subscribe(() => setTick((n) => n + 1)), [controller])
      const imageIds = useInput ? (useInput((s) => s.attachmentIds || s.imageIds) || []) : []
      const liveIds = new Set(Array.isArray(imageIds) ? imageIds : [])
      const labels = []
      const seen = new Set()
      let stale = false
      for (const [imageId, label] of [...controller.labelsByImageId]) {
        if (!liveIds.has(imageId)) {
          stale = true
          controller.labelsByImageId.delete(imageId)
          controller.previewByImageId.delete(imageId)
          continue
        }
        if (seen.has(label)) continue
        seen.add(label)
        labels.push(label)
      }
      React.useEffect(() => {
        if (stale) controller.publish()
      }, [stale])
      if (labels.length === 0) return null
      return React.createElement('div', { className: 'dsh-appshots-notice-wrap' },
        React.createElement('div', { className: 'dsh-appshots-notice', role: 'status' },
          labels.map((label) => React.createElement('div', {
            key: label,
            className: 'dsh-appshots-notice-item',
          }, `已附加 ${label} 的 Appshot`)),
        ),
      )
    }

    function AppshotButton({ controller }) {
      const [, setTick] = React.useState(0)
      React.useEffect(() => controller.subscribe(() => setTick((n) => n + 1)), [controller])
      return React.createElement('button', {
        type: 'button',
        className: 'dsh-appshots-btn',
        title: 'Appshot：捕获前台窗口',
        'data-busy': controller.busy ? 'true' : 'false',
        disabled: controller.busy,
        onClick: () => { void controller.captureFromUi() },
      }, React.createElement(CameraIcon))
    }

    function apply(ctx) {
      const controller = new AppshotController(ctx)
      ctx.effect(() => {
        const style = document.createElement('style')
        style.dataset.plugin = 'dsh-appshots'
        style.textContent = CSS
        document.head.appendChild(style)
        return () => style.remove()
      }, 'dsh-appshots: styles')
      ctx.effect(() => controller.start(), 'dsh-appshots: events')
      ctx.slots.inject('conversation.input.left', () => ctx.slots.register({
        name: 'conversation.input.left',
        id: 'appshots-button',
        order: 9600,
        label: 'Appshot',
      }, () => React.createElement(AppshotButton, { controller })))
      ctx.slots.inject('conversation.input.dock', () => ctx.slots.register({
        name: 'conversation.input.dock',
        id: 'appshots-notice',
        order: 50,
        label: 'Appshot',
      }, ({ useInput }) => React.createElement(AppshotNotice, { controller, useInput })))
      ctx.effect(() => mountLightboxOverlay(controller), 'dsh-appshots: lightbox')
    }

    exports.name = 'dsh-appshots'
    exports.apply = apply
    exports.inject = inject
    return module.exports
  },
})
