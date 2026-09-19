import { describe, expect, test } from 'claude-code/testing'

import { commandOf, mayCommit, payloadOf, read } from '../hooks/gate'

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

describe('gate', () => {
  test('a command is read off the tool input', () => {
    expect(commandOf({ command: 'git commit -m x' })).toBe(
      'git commit -m x',
    )
  })

  test('an input carrying no command reads as none', () => {
    expect(commandOf({})).toBeUndefined()
    expect(commandOf({ command: '' })).toBeUndefined()
    expect(commandOf({ command: 42 })).toBeUndefined()
    expect(commandOf(null)).toBeUndefined()
    expect(commandOf(undefined)).toBeUndefined()
  })

  // The whole point of the in-process fast path: the calls that cannot commit
  // are the overwhelming majority, and they must cost nothing.
  test('only a command mentioning a commit is worth a subprocess', () => {
    expect(mayCommit('ls -la')).toBe(false)
    expect(mayCommit('npm test')).toBe(false)
    expect(mayCommit('git status')).toBe(false)
    expect(mayCommit('git commit -m x')).toBe(true)
  })

  // Crude on purpose, and the same test the script's own fast path makes: the
  // two have to agree about what is worth looking at, and the script is the
  // one that decides what it actually is.
  test('the test is deliberately loose, not a commit detector', () => {
    expect(mayCommit('git log --format=%H -- commitments.md')).toBe(true)
    expect(mayCommit('echo "commit"')).toBe(true)
  })

  test('an empty stdout is an allow', () => {
    expect(read('')).toEqual({ kind: 'pass' })
    expect(read('   \n')).toEqual({ kind: 'pass' })
  })

  test('a deny carries its reason through', () => {
    expect(read(denied('no clean review on record'))).toEqual({
      kind: 'block',
      reason: 'no clean review on record',
    })
  })

  test('additionalContext without a decision is a warn', () => {
    const stdout = JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext: 'warn mode, nothing stops this',
      },
    })

    expect(read(stdout)).toEqual({
      kind: 'warn',
      reason: 'warn mode, nothing stops this',
    })
  })

  // Fail open, the same way the script does about its own errors: a gate that
  // refuses a commit because it could not parse something enforces nothing and
  // blocks everything.
  test('output that cannot be read is an allow', () => {
    expect(read('not json at all')).toEqual({ kind: 'pass' })
    expect(read('{"hookSpecificOutput":{}}')).toEqual({ kind: 'pass' })
    expect(read('{}')).toEqual({ kind: 'pass' })
  })

  test('a decision other than deny is an allow', () => {
    const stdout = JSON.stringify({
      hookSpecificOutput: { permissionDecision: 'allow' },
    })

    expect(read(stdout)).toEqual({ kind: 'pass' })
  })

  // The tool name rides along so the script quotes the bypass back in the
  // syntax the agent will actually type it in.
  test('the payload is the claude PreToolUse shape', () => {
    expect(JSON.parse(payloadOf('PowerShell', 'git commit', '/repo'))).toEqual({
      cwd: '/repo',
      tool_name: 'PowerShell',
      tool_input: { command: 'git commit' },
    })
  })
})
