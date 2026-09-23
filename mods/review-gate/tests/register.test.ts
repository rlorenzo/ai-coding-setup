import { describe, expect, mock, test } from 'claude-code/testing'

/**
 * Where `./setup` installs the script, and so where the hook finds it once
 * `mock.env` has said where HOME is.
 */
const INSTALLED = '/home/dev/.local/bin/review-gate'

/**
 * The claude-shaped answer the script prints on a block.
 *
 * @param reason what it says
 * @returns the stdout
 */
function denied(reason: string) {
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  })
}

/**
 * Seats the world beneath the mod: an installed script, a working directory,
 * and a bottom `tool.check` that allows whatever reaches it.
 *
 * @param on the test's registrar
 * @param stdout what the script prints when it is run
 * @returns the commands the script was run over, in order
 */
function world(on: Parameters<typeof mock.env>[0], stdout: string) {
  const consulted: string[] = []

  mock.env(on, { HOME: '/home/dev' })
  on('fs.exists', ($, e) => ({ value: e.path === INSTALLED }))
  on('session.cwd', () => ({ value: '/repo' }))
  on('process.run', ($, e) => {
    consulted.push(JSON.parse(e.init?.stdin ?? '{}').tool_input?.command ?? '')

    return { value: { exitCode: 0, stdout, stderr: '' } }
  })
  on('tool.check', () => ({ decision: 'allow' }))

  return consulted
}

/**
 * A permission decision on a shell command, as the engine raises one.
 *
 * @param command what the tool is about to run
 * @param over what this call differs in
 * @returns the event
 */
function check(command: string, over: Record<string, unknown> = {}) {
  return {
    tool: 'Bash',
    input: { command },
    tool_use_id: 'toolu_01',
    ...over,
  }
}

describe('register', () => {
  // The reason the hook exists: the script is a process start on every shell
  // call, and almost no shell call commits.
  test('a command that cannot commit never runs the script', async ($, on) => {
    const consulted = world(on, denied('should not be reached'))

    const { decision } = await $.tool.check(check('ls -la'))

    expect(decision).toBe('allow')
    expect(consulted).toEqual([])
  })

  test('a blocked commit is put to the user as a question', async ($, on) => {
    world(on, denied('no clean review on record'))

    const { decision, reason } = await $.tool.check(
      check('git commit -m "wip"'),
    )

    expect(decision).toBe('ask')
    expect(reason).toBe('no clean review on record')
  })

  test('the script sees the command it is being asked about', async ($, on) => {
    const consulted = world(on, '')

    await $.tool.check(check('git commit -m "wip"'))

    expect(consulted).toEqual(['git commit -m "wip"'])
  })

  test('a commit the script allows is allowed', async ($, on) => {
    world(on, '')

    const { decision } = await $.tool.check(check('git commit -m "reviewed"'))

    expect(decision).toBe('allow')
  })

  // Warn mode: the script chose not to stop the commit, so neither does the
  // hook. Its reasoning still reaches the transcript, where on the shell-hook
  // route it goes to a stderr nobody reads.
  test('warn output reaches the transcript and does not stop the commit', async ($, on) => {
    const logged: string[] = []

    world(
      on,
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          additionalContext: 'warn mode, nothing stops this',
        },
      }),
    )
    on('ui.log', ($, e, next) => {
      logged.push(e.text)

      return next(e)
    })

    const { decision } = await $.tool.check(check('git commit -m "wip"'))

    expect(decision).toBe('allow')
    expect(logged).toEqual(['warn mode, nothing stops this'])
  })

  // A Windows harness exposes PowerShell beside Bash, and a gate that watches
  // only Bash lets every commit made through the other one past.
  test('the PowerShell tool is gated too', async ($, on) => {
    world(on, denied('no clean review on record'))

    const { decision } = await $.tool.check(
      check('git commit -m "wip"', { tool: 'PowerShell' }),
    )

    expect(decision).toBe('ask')
  })

  test('a tool that is not a shell is not gated', async ($, on) => {
    const consulted = world(on, denied('should not be reached'))

    const { decision } = await $.tool.check({
      tool: 'Read',
      input: { file_path: '/repo/commit.md' },
      tool_use_id: 'toolu_02',
    })

    expect(decision).toBe('allow')
    expect(consulted).toEqual([])
  })

  // A query is not a call: answering one would spend the single-use nonce the
  // script issues with a block on a commit that is not happening.
  test('a permission query is passed through untouched', async ($, on) => {
    const consulted = world(on, denied('should not be reached'))

    const { decision } = await $.tool.check({
      tool: 'Bash',
      input: { command: 'git commit -m "wip"' },
    })

    expect(decision).toBe('allow')
    expect(consulted).toEqual([])
  })

  // Fail open. A hook that refuses a commit because a subprocess would not
  // start enforces nothing and blocks everything.
  test('a script that cannot be run lets the commit through', async ($, on) => {
    mock.env(on, { HOME: '/home/dev' })
    on('fs.exists', ($, e) => ({ value: e.path === INSTALLED }))
    on('session.cwd', () => ({ value: '/repo' }))
    on('process.run', () => {
      throw new Error('ENOENT')
    })
    on('tool.check', () => ({ decision: 'allow' }))

    const { decision } = await $.tool.check(check('git commit -m "wip"'))

    expect(decision).toBe('allow')
  })

  test('output the script did not mean as a decision lets the commit through', async ($, on) => {
    world(on, 'warning: something on stdout that is not json')

    const { decision } = await $.tool.check(check('git commit -m "wip"'))

    expect(decision).toBe('allow')
  })

  // Resolved once per session: this is on the path of every commit, and where
  // the script lives cannot change while the session runs.
  test('the script is looked for once, not once per commit', async ($, on) => {
    const looked: string[] = []

    mock.env(on, { HOME: '/home/dev' })
    on('fs.exists', ($, e) => {
      looked.push(e.path)

      return { value: e.path === INSTALLED }
    })
    on('session.cwd', () => ({ value: '/repo' }))
    on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }))
    on('tool.check', () => ({ decision: 'allow' }))

    await $.tool.check(check('git commit -m one'))
    await $.tool.check(check('git commit -m two'))

    expect(looked).toEqual([INSTALLED])
  })

  test('an empty HOME falls through to USERPROFILE', async ($, on) => {
    const looked: string[] = []

    mock.env(on, { HOME: '', USERPROFILE: '/home/dev' })
    on('fs.exists', ($, e) => {
      looked.push(e.path)

      return { value: e.path === INSTALLED }
    })
    on('session.cwd', () => ({ value: '/repo' }))
    on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }))
    on('tool.check', () => ({ decision: 'allow' }))

    await $.tool.check(check('git commit -m one'))

    expect(looked).toEqual([INSTALLED])
  })
})
