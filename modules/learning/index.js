import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createStore, moduleDataDir } from '../shared/store.js'
import {
  DEFAULT_PHYSICS,
  TILE_LEGEND,
  TOOL_NAMES,
  invokeTool,
  levelToRows,
  routeIntent,
  think,
} from './brain.js'
import { createMemory, MEMORY_DEFAULTS } from './memory.js'

const here = path.dirname(fileURLToPath(import.meta.url))

export const LEARNING_ID = 'learning'

function memory() {
  return createMemory(
    createStore({
      dir: moduleDataDir(LEARNING_ID),
      file: 'memory.json',
      defaults: MEMORY_DEFAULTS,
    }),
  )
}

function withRows(result) {
  if (!result?.map) return result
  return { ...result, map: { ...result.map, rows: levelToRows(result.map) } }
}

function api(router) {
  router.get('/tools', (_req, res) => {
    res.json({
      ok: true,
      tools: TOOL_NAMES,
      legend: TILE_LEGEND,
      defaultPhysics: DEFAULT_PHYSICS,
    })
  })

  router.get('/memory', (_req, res) => {
    const mem = memory()
    const state = mem.read()
    res.json({
      ok: true,
      summary: mem.summary(),
      lessons: state.lessons.map(({ triggerTokens, ...rest }) => rest),
      routes: state.routes,
      recent: state.interactions.slice(0, 10),
    })
  })

  router.post('/ask', (req, res, next) => {
    try {
      const message = String(req.body?.message || '').trim()
      if (!message) {
        throw Object.assign(new Error('Ask me something first.'), { status: 400 })
      }
      const mem = memory()

      // 1. Something you taught wins outright.
      const recalled = mem.recall(message)
      if (recalled) {
        mem.markRecalled(recalled.lesson.id)
        const interaction = mem.recordInteraction({ message, tool: 'recall', source: 'learned' })
        res.json({
          ok: true,
          source: 'learned',
          interactionId: interaction.id,
          text: recalled.lesson.response,
          learnedFrom: { trigger: recalled.lesson.trigger, score: recalled.score },
          summary: mem.summary(),
        })
        return
      }

      // 2. Otherwise Free Brain, with the routing you have trained applied on
      //    top: promoted tools win outright, rejected ones are skipped.
      const untrained = routeIntent(message)
      const preferred = mem.routePreference(message)
      const demoted = mem.demotedTools(message)

      let reply
      if (preferred) {
        const result = invokeTool(preferred, {
          ...(untrained?.args || {}),
          prompt: message,
          question: message,
          description: message,
        })
        reply = { source: 'free-brain', tool: preferred, text: result.message, result }
      } else {
        reply = think(message, { physics: req.body?.physics, exclude: demoted })
      }

      const interaction = mem.recordInteraction({
        message,
        tool: reply.tool,
        source: reply.source,
      })
      res.json({
        ok: true,
        source: reply.source,
        tool: reply.tool,
        trainedRouting: Boolean(reply.tool && untrained && reply.tool !== untrained.tool),
        interactionId: interaction.id,
        text: reply.text,
        result: withRows(reply.result),
        summary: mem.summary(),
      })
    } catch (err) {
      next(err)
    }
  })

  router.post('/teach', (req, res, next) => {
    try {
      const lesson = memory().teach({
        trigger: req.body?.trigger,
        response: req.body?.response,
      })
      const { triggerTokens, ...rest } = lesson
      res.status(201).json({
        ok: true,
        message: `Learned. Ask me “${lesson.trigger}” and I will answer that from now on.`,
        lesson: rest,
        summary: memory().summary(),
      })
    } catch (err) {
      next(err)
    }
  })

  router.delete('/memory/:id', (req, res, next) => {
    try {
      const removed = memory().forget(req.params.id)
      if (!removed) {
        throw Object.assign(new Error('No such lesson.'), { status: 404 })
      }
      res.json({ ok: true, message: `Forgot “${removed.trigger}”.`, summary: memory().summary() })
    } catch (err) {
      next(err)
    }
  })

  router.post('/feedback', (req, res, next) => {
    try {
      const mem = memory()
      const interaction = mem.reinforce({
        interactionId: req.body?.interactionId,
        helpful: Boolean(req.body?.helpful),
        preferTool: req.body?.preferTool,
      })
      res.json({
        ok: true,
        message: interaction.feedback === 'good' ? 'Noted — more of that.' : 'Noted — I will route that differently.',
        summary: mem.summary(),
      })
    } catch (err) {
      next(err)
    }
  })

  router.post('/tools/:name', (req, res, next) => {
    try {
      if (!TOOL_NAMES.includes(req.params.name)) {
        throw Object.assign(new Error(`Unknown tool. Available: ${TOOL_NAMES.join(', ')}.`), {
          status: 404,
        })
      }
      const result = invokeTool(req.params.name, req.body || {})
      res.json({ ok: true, result: withRows(result), text: result.message })
    } catch (err) {
      next(err)
    }
  })

  router.use((err, _req, res, _next) => {
    res.status(err.status || 500).json({ ok: false, message: err.message || String(err) })
  })
}

export const learningModule = {
  id: LEARNING_ID,
  name: 'Learning',
  version: '2.0.0',
  kind: 'learning',
  description:
    'Free Brain game-design intelligence that remembers what you teach it. Runs on its own, offline, no fingerprint unlock needed.',
  publicDir: path.join(here, 'public'),
  extraStatic: {
    '/brain.js': path.join(here, 'brain.js'),
    '/gospel.css': path.join(here, '..', 'shared', 'public', 'gospel.css'),
  },
  bodyLimit: '1mb',
  manifest: {
    name: 'Gospel Learning',
    short_name: 'Learning',
    description: 'On-device game design brain that learns from you.',
    theme_color: '#0b0d0c',
  },
  api,
}

export default learningModule
