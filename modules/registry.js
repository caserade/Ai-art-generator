import artScanModule from './art-scan/index.js'
import learningModule from './learning/index.js'

/** Mount prefix used when modules are hosted inside the main Gospel app. */
export const MODULE_MOUNT = '/m'

export const MODULES = [artScanModule, learningModule]

export function getModule(id) {
  return MODULES.find((m) => m.id === id) || null
}

export function moduleIds() {
  return MODULES.map((m) => m.id)
}

export function mountPathFor(id) {
  return `${MODULE_MOUNT}/${id}/`
}

/** Default standalone port per module, overridable with --port / PORT. */
export const DEFAULT_PORTS = {
  'art-scan': 8790,
  learning: 8791,
}
