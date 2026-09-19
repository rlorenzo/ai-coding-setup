/**
 * The parts of the gate that touch nothing: what a command is, whether it is
 * worth a subprocess, what to feed the script and how to read what it says.
 *
 * None of it takes `$`. The engine follows `$` only into a function declared
 * in the file the hook is in and never across an import, so everything that
 * calls a noun lives in register.ts and everything testable on its own lives
 * here.
 */

/**
 * What a shell tool's input looks like where it carries a command. The
 * permission decision reads Bash as `{ command }`; the PowerShell tool a
 * Windows harness exposes alongside it is the same shape.
 */
type ShellInput = {
  command?: unknown
}

/**
 * The claude-shaped answer `bin/review-gate --format=claude` prints: a deny
 * carries a decision and a reason, a warn carries context and no decision, and
 * an allow is an empty stdout.
 */
type GateOutput = {
  hookSpecificOutput?: {
    permissionDecision?: string
    permissionDecisionReason?: string
    additionalContext?: string
  }
}

/**
 * What the hook does with a command, once the gate has spoken.
 *
 * `pass` covers every allow, including the ones the gate never saw.
 */
export type Verdict =
  | { kind: 'pass' }
  | { kind: 'block'; reason: string }
  | { kind: 'warn'; reason: string }

/**
 * Where `./setup` installs the script, under the home directory.
 */
export const INSTALLED = '/.local/bin/review-gate'

/**
 * The bare name, left to the child's own PATH lookup when no absolute path
 * answers: `$.fs.exists` cannot search a PATH.
 */
export const ON_PATH = 'review-gate'

/**
 * The substring every commit command contains. Tested before anything else
 * runs, because this hook is asked about every shell call the agent makes and
 * almost none of them commit.
 *
 * Deliberately the same crude test the script's own fast path makes: the two
 * have to agree about what is worth looking at, and a cheap false positive
 * costs one subprocess where a false negative would let a commit through
 * unseen.
 */
const COMMIT = 'commit'

/**
 * The command a shell tool call will run, where it has one.
 *
 * @param input the tool's arguments as the permission decision reads them
 * @returns the command, or undefined where the input carries none
 */
export function commandOf(input: unknown): string | undefined {
  const command = (input as ShellInput | null)?.command

  return typeof command === 'string' && command !== '' ? command : undefined
}

/**
 * Whether a command could possibly be a commit.
 *
 * @param command the command the tool is about to run
 * @returns false when nothing further need be asked about it
 */
export function mayCommit(command: string): boolean {
  return command.includes(COMMIT)
}

/**
 * What the script reads on stdin: the claude PreToolUse shape, which its own
 * `--format=claude` already speaks.
 *
 * The tool name rides along so the script quotes the bypass back in the syntax
 * the agent will actually type it in -- a bash `VAR=value cmd` prefix is a hard
 * parse error in PowerShell.
 *
 * @param tool the tool as the model names it
 * @param command the command the tool is about to run
 * @param cwd the session's working directory
 * @returns the payload
 */
export function payloadOf(tool: string, command: string, cwd: string): string {
  return JSON.stringify({ cwd, tool_name: tool, tool_input: { command } })
}

/**
 * Reads the script's stdout.
 *
 * Fails open on anything unexpected, the same way the script does about its
 * own errors: a gate that refuses a commit because it could not parse
 * something enforces nothing and blocks everything.
 *
 * @param stdout what the script printed
 * @returns what to do with the command
 */
export function read(stdout: string): Verdict {
  const text = stdout.trim()

  if (text === '') {
    return { kind: 'pass' }
  }

  let output: GateOutput

  try {
    output = JSON.parse(text) as GateOutput
  } catch {
    return { kind: 'pass' }
  }

  const said = output.hookSpecificOutput

  if (said?.permissionDecision === 'deny') {
    return { kind: 'block', reason: said.permissionDecisionReason ?? '' }
  }

  if (typeof said?.additionalContext === 'string') {
    return { kind: 'warn', reason: said.additionalContext }
  }

  return { kind: 'pass' }
}
