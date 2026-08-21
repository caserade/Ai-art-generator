import fs from 'node:fs'
import path from 'node:path'

/**
 * Tiny atomic JSON store. Each module gets its own file under its own data
 * directory so a module keeps working when the main Gospel state is missing,
 * corrupt, or locked by another process.
 */
export function createStore({ dir, file, defaults = {} }) {
  const filePath = path.join(dir, file)

  function ensureDir() {
    fs.mkdirSync(dir, { recursive: true })
  }

  function read() {
    try {
      const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'))
      return { ...structuredClone(defaults), ...raw }
    } catch {
      return structuredClone(defaults)
    }
  }

  function write(value) {
    ensureDir()
    const tmp = `${filePath}.${process.pid}.tmp`
    fs.writeFileSync(tmp, JSON.stringify(value, null, 2))
    fs.renameSync(tmp, filePath)
    return value
  }

  function update(mutator) {
    const current = read()
    const next = mutator(current) ?? current
    return write(next)
  }

  return { read, write, update, filePath, dir, ensureDir }
}

/** Resolve a module's private data directory. */
export function moduleDataDir(moduleId) {
  const root =
    process.env.GOSPEL_MODULE_DATA_DIR ||
    process.env.GOSPEL_DATA_DIR ||
    path.join(process.cwd(), 'data')
  return path.join(root, moduleId)
}
