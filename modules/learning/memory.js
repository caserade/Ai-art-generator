/**
 * Learning memory.
 *
 * Free Brain on its own is a fixed set of heuristics: ask it the same thing
 * twice and you get the same answer forever. This layer is what makes the
 * module actually *learn* — it persists two things to the module's own disk
 * store so they survive restarts:
 *
 *   lessons  things you explicitly taught it ("when I say X, answer Y")
 *   routes   per-phrase tool weights adjusted by your thumbs up/down
 *
 * Both are consulted before the heuristics, so the module's answers change
 * based on what it has been told.
 */

const STOPWORDS = new Set([
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'can', 'do', 'does',
  'for', 'from', 'get', 'has', 'have', 'how', 'i', 'if', 'in', 'is', 'it',
  'its', 'me', 'my', 'of', 'on', 'or', 'so', 'that', 'the', 'their', 'them',
  'then', 'there', 'they', 'this', 'to', 'was', 'what', 'when', 'why', 'will',
  'with', 'you', 'your',
])

const MAX_LESSONS = 500
const MAX_INTERACTIONS = 100
const RECALL_THRESHOLD = 0.5
const ROUTE_MARGIN = 2

export const MEMORY_DEFAULTS = {
  lessons: [],
  routes: {},
  interactions: [],
  stats: { asked: 0, taught: 0, recalled: 0, feedback: 0 },
}

export function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter((w) => w.length > 2 && !STOPWORDS.has(w))
}

/** Stable key for "messages that mean roughly this". */
export function signature(text) {
  const tokens = [...new Set(tokenize(text))].sort()
  return tokens.slice(0, 6).join(' ')
}

export function similarity(aTokens, bTokens) {
  const a = new Set(aTokens)
  const b = new Set(bTokens)
  if (!a.size || !b.size) return 0
  let shared = 0
  for (const token of a) if (b.has(token)) shared += 1
  return shared / (a.size + b.size - shared)
}

function newId(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
}

export function createMemory(store) {
  function read() {
    const state = store.read()
    return {
      ...MEMORY_DEFAULTS,
      ...state,
      stats: { ...MEMORY_DEFAULTS.stats, ...(state.stats || {}) },
    }
  }

  function teach({ trigger, response }) {
    const cleanTrigger = String(trigger || '').trim()
    const cleanResponse = String(response || '').trim()
    if (!cleanTrigger) throw Object.assign(new Error('Teach needs a trigger phrase.'), { status: 400 })
    if (!cleanResponse) throw Object.assign(new Error('Teach needs a response to learn.'), { status: 400 })
    const tokens = tokenize(cleanTrigger)
    if (!tokens.length) {
      throw Object.assign(
        new Error('That trigger is all filler words — give me something distinctive.'),
        { status: 400 },
      )
    }

    let lesson
    store.update((state) => {
      const lessons = state.lessons || []
      // Re-teaching the same trigger updates it instead of piling up duplicates.
      const existing = lessons.find((l) => similarity(l.triggerTokens || [], tokens) >= 0.9)
      if (existing) {
        existing.trigger = cleanTrigger
        existing.triggerTokens = tokens
        existing.response = cleanResponse
        existing.updatedAt = Date.now()
        lesson = existing
      } else {
        lesson = {
          id: newId('lesson'),
          trigger: cleanTrigger,
          triggerTokens: tokens,
          response: cleanResponse,
          hits: 0,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        }
        state.lessons = [lesson, ...lessons].slice(0, MAX_LESSONS)
      }
      state.stats = { ...MEMORY_DEFAULTS.stats, ...(state.stats || {}) }
      state.stats.taught += 1
      return state
    })
    return lesson
  }

  function forget(id) {
    let removed = null
    store.update((state) => {
      removed = (state.lessons || []).find((l) => l.id === id) || null
      state.lessons = (state.lessons || []).filter((l) => l.id !== id)
      return state
    })
    return removed
  }

  /** Best taught lesson for a message, or null. */
  function recall(message) {
    const tokens = tokenize(message)
    if (!tokens.length) return null
    const { lessons } = read()
    let best = null
    let bestScore = 0
    for (const lesson of lessons) {
      const score = similarity(tokens, lesson.triggerTokens || tokenize(lesson.trigger))
      if (score > bestScore) {
        bestScore = score
        best = lesson
      }
    }
    if (!best || bestScore < RECALL_THRESHOLD) return null
    return { lesson: best, score: Number(bestScore.toFixed(3)) }
  }

  function markRecalled(lessonId) {
    store.update((state) => {
      const lesson = (state.lessons || []).find((l) => l.id === lessonId)
      if (lesson) {
        lesson.hits = (lesson.hits || 0) + 1
        lesson.lastUsedAt = Date.now()
      }
      state.stats = { ...MEMORY_DEFAULTS.stats, ...(state.stats || {}) }
      state.stats.recalled += 1
      return state
    })
  }

  /**
   * Tool this phrase has been trained to prefer.
   *
   * Only overrides the heuristic once one tool is clearly ahead, so a single
   * stray tap cannot rewire routing.
   */
  function routePreference(message) {
    const key = signature(message)
    if (!key) return null
    const weights = read().routes[key]
    if (!weights) return null
    const ranked = Object.entries(weights).sort((a, b) => b[1] - a[1])
    if (!ranked.length || ranked[0][1] < ROUTE_MARGIN) return null
    const runnerUp = ranked[1]?.[1] ?? 0
    if (ranked[0][1] - runnerUp < ROUTE_MARGIN) return null
    return ranked[0][0]
  }

  function recordInteraction({ message, tool, source }) {
    const interaction = {
      id: newId('turn'),
      message: String(message || '').slice(0, 400),
      tool: tool || null,
      source: source || 'free-brain',
      feedback: null,
      createdAt: Date.now(),
    }
    store.update((state) => {
      state.interactions = [interaction, ...(state.interactions || [])].slice(0, MAX_INTERACTIONS)
      state.stats = { ...MEMORY_DEFAULTS.stats, ...(state.stats || {}) }
      state.stats.asked += 1
      return state
    })
    return interaction
  }

  /**
   * Apply feedback to an answer. Helpful reinforces the tool that produced it;
   * unhelpful pushes it down so a different tool can win next time.
   */
  function reinforce({ interactionId, helpful, preferTool }) {
    let updated = null
    store.update((state) => {
      const interaction = (state.interactions || []).find((i) => i.id === interactionId)
      if (!interaction) return state
      interaction.feedback = helpful ? 'good' : 'bad'
      updated = interaction

      const key = signature(interaction.message)
      if (key && interaction.tool) {
        state.routes = state.routes || {}
        const weights = { ...(state.routes[key] || {}) }
        weights[interaction.tool] = (weights[interaction.tool] || 0) + (helpful ? 1 : -1)
        if (!helpful && preferTool) {
          weights[preferTool] = (weights[preferTool] || 0) + ROUTE_MARGIN
        }
        state.routes[key] = weights
      }

      state.stats = { ...MEMORY_DEFAULTS.stats, ...(state.stats || {}) }
      state.stats.feedback += 1
      return state
    })
    if (!updated) {
      throw Object.assign(new Error('Unknown interaction. Ask something first.'), { status: 404 })
    }
    return updated
  }

  function summary() {
    const state = read()
    return {
      lessons: state.lessons.length,
      trainedPhrases: Object.keys(state.routes).length,
      ...state.stats,
    }
  }

  return {
    read,
    teach,
    forget,
    recall,
    markRecalled,
    routePreference,
    recordInteraction,
    reinforce,
    summary,
  }
}
