import type { PluginOptions } from 'claude-code'

/**
 * The agents pinned when the `agents` option names none: the built-in
 * read-only search agent, the one Claude dispatches on its own.
 */
const DEFAULT_AGENTS: readonly string[] = ['Explore']

/**
 * The model pinned when the `model` option names none.
 */
const DEFAULT_MODEL = 'haiku'

/**
 * The `model` value that registers no hook, for turning the mod off without
 * uninstalling it.
 */
const INHERIT = 'inherit'

/**
 * The model the named agents run on.
 *
 * A blank or absent value reads as unset rather than as "pin nothing": an
 * empty `model` would otherwise pin every recon spawn to the empty string.
 *
 * @param options the plugin's options
 * @returns the model alias or id, trimmed
 */
function modelOf(options: PluginOptions): string {
  const given = options.model

  return typeof given === 'string' && given.trim() !== ''
    ? given.trim()
    : DEFAULT_MODEL
}

/**
 * Whether the options ask for no hook at all.
 *
 * @param options the plugin's options
 * @returns true when every spawn is left as the engine resolves it
 */
function isInherited(options: PluginOptions): boolean {
  return modelOf(options) === INHERIT
}

/**
 * The subagent types the hook decides.
 *
 * A `multiple` string option arrives as an array, but a single `--config
 * agents=...` pass arrives as one bare string, so both are read.
 *
 * @param options the plugin's options
 * @returns the agent names, blanks dropped
 */
function agentsOf(options: PluginOptions): readonly string[] {
  const given = options.agents
  const listed = Array.isArray(given)
    ? given
    : typeof given === 'string'
      ? given.split(',')
      : []
  const named = listed.map(agent => agent.trim()).filter(agent => agent !== '')

  return named.length > 0 ? named : DEFAULT_AGENTS
}

/**
 * Whether each pin is announced on the spawn it belongs to.
 *
 * @param options the plugin's options
 * @returns true when the hook attaches a notice
 */
function isAnnounced(options: PluginOptions): boolean {
  return options.notice === true
}

export default { agentsOf, isAnnounced, isInherited, modelOf }
