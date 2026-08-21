#!/usr/bin/env node
import { realpathSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { createModuleApp } from './host.js'
import { DEFAULT_PORTS, MODULES, getModule, moduleIds } from './registry.js'

/**
 * Run Gospel modules as their own processes, with no main app involved.
 *
 *   node modules/serve.js art-scan            # own port, own data dir
 *   node modules/serve.js learning --port 9100
 *   node modules/serve.js all                 # every module, one port each
 *
 * This is the "separate from the main app" path: if the Gospel Command server is
 * down, unenrolled or locked, these still serve the phone.
 */

function parseArgs(argv) {
  const args = { targets: [], port: null, host: '0.0.0.0' }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--port' || arg === '-p') {
      args.port = Number(argv[i + 1])
      i += 1
    } else if (arg === '--host') {
      args.host = argv[i + 1]
      i += 1
    } else if (arg === '--help' || arg === '-h') {
      args.help = true
    } else if (!arg.startsWith('-')) {
      args.targets.push(arg)
    }
  }
  return args
}

function usage() {
  return [
    'Usage: node modules/serve.js <module|all> [--port N] [--host H]',
    `Modules: ${moduleIds().join(', ')}`,
    'Env: GOSPEL_MODULE_DATA_DIR or GOSPEL_DATA_DIR sets where module data lives.',
  ].join('\n')
}

export function startModule(descriptor, { port, host = '0.0.0.0' } = {}) {
  const app = createModuleApp(descriptor)
  const resolved = port || DEFAULT_PORTS[descriptor.id] || 0
  return new Promise((resolve) => {
    const server = app.listen(resolved, host, () => {
      const actual = server.address().port
      console.log(`[${descriptor.id}] ${descriptor.name} standalone on http://${host}:${actual}/`)
      resolve({ server, port: actual, descriptor })
    })
  })
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help || !args.targets.length) {
    console.log(usage())
    process.exit(args.help ? 0 : 1)
  }

  const wantAll = args.targets.includes('all')
  const selected = wantAll
    ? MODULES
    : args.targets.map((id) => {
        const descriptor = getModule(id)
        if (!descriptor) {
          console.error(`Unknown module "${id}".\n${usage()}`)
          process.exit(1)
        }
        return descriptor
      })

  if (selected.length > 1 && args.port) {
    console.error('--port only applies to a single module; drop it when serving several.')
    process.exit(1)
  }

  const envPort = Number(process.env.PORT) || null
  for (const descriptor of selected) {
    await startModule(descriptor, {
      port: selected.length === 1 ? args.port || envPort : null,
      host: args.host,
    })
  }
  console.log('Modules run independently of WWW Gospel Command. Ctrl-C to stop.')
}

function invokedDirectly() {
  if (!process.argv[1]) return false
  try {
    return realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
  } catch {
    return false
  }
}

if (invokedDirectly()) {
  await main()
}
