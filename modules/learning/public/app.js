import { TILE_LEGEND } from './brain.js'

/**
 * Learning phone client. The brain and its memory live on the module's own
 * server; this is the phone-shaped front end for them.
 */

const QUICK_PROMPTS = [
  'make a floaty gem-hunt platformer',
  'generate a hazard gauntlet map',
  'make it feel like Celeste',
  'how should I scan my character art?',
]

const el = (id) => document.getElementById(id)
const statusEl = el('status')
const threadEl = el('thread')
const messageInput = el('message')

function setStatus(text, kind = '') {
  statusEl.textContent = text
  statusEl.className = `status ${kind}`
}

async function api(pathname, options) {
  const res = await fetch(pathname, options)
  const data = await res.json().catch(() => ({}))
  if (!res.ok || data.ok === false) throw new Error(data.message || `HTTP ${res.status}`)
  return data
}

function addTurn(role, text, tag) {
  const div = document.createElement('div')
  div.className = `turn ${role}`
  if (tag) {
    const label = document.createElement('span')
    label.className = 'tag'
    label.textContent = tag
    div.append(label)
  }
  div.append(document.createTextNode(text))
  threadEl.append(div)
  div.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  return div
}

function addMap(container, map) {
  if (!map?.rows) return
  const pre = document.createElement('div')
  pre.className = 'map'
  pre.textContent = `${map.rows.join('\n')}\n\n${TILE_LEGEND}`
  container.append(pre)
}

function addFeedback(container, interactionId) {
  if (!interactionId) return
  const wrap = document.createElement('div')
  wrap.className = 'rate'
  const send = async (helpful, button) => {
    for (const b of wrap.querySelectorAll('button')) b.disabled = true
    try {
      const data = await api('api/feedback', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ interactionId, helpful }),
      })
      button.textContent = helpful ? 'Thanks' : 'Retrained'
      setStatus(data.message, 'ok')
      await loadMemory()
    } catch (err) {
      setStatus(err.message || String(err), 'bad')
      for (const b of wrap.querySelectorAll('button')) b.disabled = false
    }
  }
  const good = document.createElement('button')
  good.textContent = 'Helpful'
  good.addEventListener('click', () => send(true, good))
  const bad = document.createElement('button')
  bad.textContent = 'Not what I meant'
  bad.addEventListener('click', () => send(false, bad))
  wrap.append(good, bad)
  container.append(wrap)
}

async function ask(message) {
  const text = String(message || '').trim()
  if (!text) return
  addTurn('you', text)
  messageInput.value = ''
  el('send').disabled = true
  setStatus('Thinking on-device…', 'busy')
  try {
    const data = await api('api/ask', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text }),
    })
    const tag =
      data.source === 'learned'
        ? `Learned · from “${data.learnedFrom.trigger}”`
        : `Free Brain · ${data.tool}${data.trainedRouting ? ' · trained routing' : ''}`
    const turn = addTurn('brain', data.text, tag)
    addMap(turn, data.result?.map)
    addFeedback(turn, data.interactionId)
    setStatus(
      `Learned ${data.summary.lessons} lesson${data.summary.lessons === 1 ? '' : 's'} across ${data.summary.asked} questions.`,
      'ok',
    )
    await loadMemory()
  } catch (err) {
    setStatus(err.message || String(err), 'bad')
  } finally {
    el('send').disabled = false
  }
}

async function loadMemory() {
  try {
    const data = await api('api/memory')
    const s = data.summary
    el('memorySummary').textContent =
      `${s.lessons} lesson${s.lessons === 1 ? '' : 's'} · ${s.trainedPhrases} trained phrase${s.trainedPhrases === 1 ? '' : 's'} · ` +
      `${s.asked} asked · ${s.recalled} answered from memory · ${s.feedback} ratings.`
    const list = el('lessons')
    list.innerHTML = ''
    for (const lesson of data.lessons) {
      const li = document.createElement('li')
      const title = document.createElement('strong')
      title.textContent = lesson.trigger
      const body = document.createElement('span')
      body.textContent = lesson.response
      const meta = document.createElement('span')
      meta.textContent = `used ${lesson.hits} time${lesson.hits === 1 ? '' : 's'}`
      const forget = document.createElement('button')
      forget.className = 'danger'
      forget.textContent = 'Forget'
      forget.addEventListener('click', async () => {
        forget.disabled = true
        try {
          const result = await api(`api/memory/${lesson.id}`, { method: 'DELETE' })
          setStatus(result.message, 'ok')
          await loadMemory()
        } catch (err) {
          setStatus(err.message || String(err), 'bad')
          forget.disabled = false
        }
      })
      li.append(title, body, meta, forget)
      list.append(li)
    }
  } catch (err) {
    el('memorySummary').textContent = `Memory unavailable: ${err.message || err}`
  }
}

el('send').addEventListener('click', () => void ask(messageInput.value))
messageInput.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault()
    void ask(messageInput.value)
  }
})

el('teach').addEventListener('click', async () => {
  const button = el('teach')
  button.disabled = true
  try {
    const data = await api('api/teach', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        trigger: el('trigger').value,
        response: el('response').value,
      }),
    })
    setStatus(data.message, 'ok')
    el('trigger').value = ''
    el('response').value = ''
    await loadMemory()
  } catch (err) {
    setStatus(err.message || String(err), 'bad')
  } finally {
    button.disabled = false
  }
})

el('refresh').addEventListener('click', () => void loadMemory())

function renderChips() {
  const chips = el('chips')
  for (const prompt of QUICK_PROMPTS) {
    const chip = document.createElement('button')
    chip.className = 'chip'
    chip.textContent = prompt
    chip.addEventListener('click', () => void ask(prompt))
    chips.append(chip)
  }
}

async function boot() {
  renderChips()
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(() => {})
  }
  try {
    const health = await api('api/health')
    el('nav').hidden = health.standalone
    setStatus(
      health.standalone
        ? 'Learning is running on its own. Ask it anything.'
        : 'Learning ready — running independently of the Gospel unlock.',
      'ok',
    )
  } catch {
    setStatus('Learning server unreachable. Reconnect to ask or teach.', 'bad')
  }
  await loadMemory()
}

void boot()
