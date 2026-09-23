import type { On, PluginOptions } from 'claude-code'

import Options from './options'

/**
 * Registers the spawn hook that pins the recon agents' model.
 *
 * Since Claude Code v2.1.198 the built-in `Explore` subagent inherits the
 * main session's model, so a session on an expensive model pays that tier for
 * every background codebase search Claude delegates. A user-level agent file
 * of the same name overrides the built-in and can set `model:`, but a
 * replacement definition is loaded like any other subagent, which means it
 * also loads CLAUDE.md and user memory that the built-in skips for speed.
 *
 * Setting `model` on the spawn costs neither: the definition that runs is
 * still the built-in, and only what it runs on changes.
 *
 * Two spawns are left exactly as they came. A fork inherits the parent's
 * context and model and ignores `model` outright, so rewriting it would say
 * something untrue about what happens. A spawn that named its own model was
 * an explicit choice by the caller, and the case this hook is here to decide
 * is the one nobody decided.
 *
 * @param on the engine's registrar
 * @param options the plugin's options: `model`, `agents` and `notice`
 */
export function register(on: On, options: PluginOptions): void {
  if (Options.isInherited(options)) {
    return
  }

  const model = Options.modelOf(options)
  const isAnnounced = Options.isAnnounced(options)

  on('agent.spawn', { subagentType: Options.agentsOf(options) }, ($, e, next) => {
    if (e.fork || e.model !== undefined) {
      return next(e)
    }

    if (isAnnounced) {
      $.ui.notice(e.tool_use_id, `${e.subagentType} pinned to ${model}`)
    }

    return next({ ...e, model })
  })
}
