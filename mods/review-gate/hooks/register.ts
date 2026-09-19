import type { EngineInterface, On, PluginOptions } from 'claude-code'

import type { Verdict } from './gate'
import { INSTALLED, ON_PATH, commandOf, mayCommit, payloadOf, read } from './gate'

/**
 * The tools that run a command. A Windows harness exposes PowerShell alongside
 * Bash, and a matcher naming Bash alone would let every commit made through
 * the other one straight past -- the same blind spot `./setup` writes
 * `Bash|PowerShell` to close for the shell-hook route.
 */
const SHELLS: readonly string[] = ['Bash', 'PowerShell']

/**
 * What a blocked commit does when the option names nothing.
 */
const DEFAULT_BLOCKED = 'ask'

/**
 * How long the script may run before the call is abandoned and the commit
 * allowed. It is sub-second git plumbing by design; this is only a bound on a
 * pathological repository.
 */
const TIMEOUT_MS = 15_000

/**
 * Where `bin/review-gate` is, or the bare name for the child's own PATH lookup
 * when no absolute path answers.
 *
 * Declared here rather than beside the rest of the gate because the engine
 * follows `$` only into a function declared in the file the hook is in.
 *
 * @param $ the engine
 * @param configured the `gate` option, where one is set
 * @returns the path or command name to run, or undefined to stand down
 */
async function locate(
  $: EngineInterface,
  configured: string | undefined,
): Promise<string | undefined> {
  if (configured !== undefined && configured !== '') {
    return (await $.fs.exists(configured)) ? configured : undefined
  }

  const named = await $.env.get('AI_REVIEW_GATE_BIN')

  if (named !== undefined && named !== '' && (await $.fs.exists(named))) {
    return named
  }

  const home = (await $.env.get('HOME')) ?? (await $.env.get('USERPROFILE'))

  if (home !== undefined && (await $.fs.exists(`${home}${INSTALLED}`))) {
    return `${home}${INSTALLED}`
  }

  return ON_PATH
}

/**
 * Runs the script over one command and reads its answer.
 *
 * Nothing here knows how the gate decides -- which commands commit, what a
 * receipt has to match, when a rewrite is in progress -- only how it reports.
 * That is the point: one implementation of the rules, in the script, under its
 * own tests, with no second copy to drift.
 *
 * @param $ the engine
 * @param gate where the script is
 * @param tool the tool as the model names it
 * @param command the command the tool is about to run
 * @param cwd the session's working directory
 * @returns what to do with the command
 */
async function consult(
  $: EngineInterface,
  gate: string,
  tool: string,
  command: string,
  cwd: string,
): Promise<Verdict> {
  try {
    const run = await $.process.run([gate, '--format=claude'], {
      cwd,
      stdin: payloadOf(tool, command, cwd),
      timeoutMs: TIMEOUT_MS,
    })

    return read(run.stdout)
  } catch {
    // Fail open. A hook that refuses a commit because a subprocess would not
    // start enforces nothing and blocks everything.
    return { kind: 'pass' }
  }
}

/**
 * Registers the gate on the permission decision.
 *
 * `bin/review-gate` already does this as a `PreToolUse` shell hook, and still
 * does for the four harnesses that have no other way. Running it here instead
 * buys two things a spawned hook cannot have.
 *
 * The first is the calls it never sees. The hook is asked about every command
 * the agent runs, overwhelmingly `ls`, `cat` and test runs, and each one pays
 * a process start: about 160ms under Git Bash on Windows against 55ms for a
 * bare `bash -c true`. Here that question is a substring test in the engine's
 * own process, and the script is spawned only for a command that could
 * actually be a commit.
 *
 * The second is `ask`. A `PreToolUse` hook may allow or deny, so the script
 * has to choose between refusing a commit outright and letting it through with
 * a warning -- which is why it ships in `warn`, and why handing the question
 * back to the person is something its own docs describe as out of reach. A
 * `tool.check` hook may answer `ask`, so the gate's reason goes to whoever the
 * commit belongs to.
 *
 * @param on the engine's registrar
 * @param options the plugin's options: `blocked` and `gate`
 */
export function register(on: On, options: PluginOptions): void {
  const blocked = options.blocked === 'deny' ? 'deny' : DEFAULT_BLOCKED
  const configured =
    typeof options.gate === 'string' && options.gate !== ''
      ? options.gate
      : undefined

  // Looked for once, on the first commit-shaped command rather than at
  // registration: `register` is synchronous, and where the script lives cannot
  // change while the session runs. Held as the promise rather than its value,
  // so two commits in flight at once share the one lookup.
  let finding: Promise<string | undefined> | undefined

  on('tool.check', { tool: SHELLS }, async ($, e, next) => {
    // A query is not a call. Answering one would spend the single-use nonce
    // the script issues with a block on a commit that is not happening; the
    // real call that follows is decided on its own.
    if (e.tool_use_id === undefined) {
      return next(e)
    }

    const command = commandOf(e.input)

    if (command === undefined || !mayCommit(command)) {
      return next(e)
    }

    finding ??= locate($, configured)

    const gate = await finding

    if (gate === undefined) {
      return next(e)
    }

    const cwd = await $.session.cwd()
    const verdict = await consult($, gate, e.tool, command, cwd)

    if (verdict.kind === 'pass') {
      return next(e)
    }

    // Warn mode: the script decided not to stop the commit, so neither does
    // this. Its reasoning still goes somewhere a person can read it, which on
    // the shell-hook route is a stderr nobody looks at.
    if (verdict.kind === 'warn') {
      $.ui.log(verdict.reason, 'transcript')

      return next(e)
    }

    return { decision: blocked, reason: verdict.reason }
  })
}
