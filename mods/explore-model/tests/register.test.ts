import { describe, expect, test } from 'claude-code/testing'

/**
 * A spawn as the Agent tool raises one, with the fields the hook reads.
 *
 * @param over what this spawn differs in
 * @returns the event
 */
function spawn(over: Record<string, unknown> = {}) {
  return {
    tool_use_id: 'toolu_01',
    prompt: 'find where the gate reads its receipts',
    description: 'locate receipts',
    subagentType: 'Explore',
    provider: { plugin: 'engine', tier: 'core' },
    parentModel: 'claude-opus-5',
    background: false,
    fork: false,
    ...over,
  }
}

describe('register', () => {
  test('an Explore spawn that named no model runs on haiku', async ($, on) => {
    on('agent.spawn', ($, e) => ({ model: e.model ?? 'inherited' }))

    const { model } = await $.agent.spawn(spawn())

    expect(model).toBe('haiku')
  })

  test('a spawn that named its own model keeps it', async ($, on) => {
    on('agent.spawn', ($, e) => ({ model: e.model ?? 'inherited' }))

    const { model } = await $.agent.spawn(spawn({ model: 'opus' }))

    expect(model).toBe('opus')
  })

  // A fork inherits the parent's context and model and ignores `model`
  // outright, so setting one would only misdescribe what happens.
  test('a fork is left alone', async ($, on) => {
    on('agent.spawn', ($, e) => ({ model: e.model ?? 'inherited' }))

    const { model } = await $.agent.spawn(spawn({ fork: true }))

    expect(model).toBe('inherited')
  })

  test('an agent the options do not name is left alone', async ($, on) => {
    on('agent.spawn', ($, e) => ({ model: e.model ?? 'inherited' }))

    const { model } = await $.agent.spawn(
      spawn({ subagentType: 'general-purpose' }),
    )

    expect(model).toBe('inherited')
  })

  // Everything else about the spawn is the caller's; the hook rewrites one
  // field and must hand the rest through untouched.
  test('the rest of the spawn is handed through untouched', async ($, on) => {
    let seen: Record<string, unknown> | undefined

    on('agent.spawn', ($, e) => {
      seen = e as unknown as Record<string, unknown>

      return { model: e.model ?? 'inherited' }
    })

    await $.agent.spawn(spawn({ prompt: 'sweep the tokenizer' }))

    expect(seen?.prompt).toBe('sweep the tokenizer')
    expect(seen?.subagentType).toBe('Explore')
    expect(seen?.parentModel).toBe('claude-opus-5')
    expect(seen?.background).toBe(false)
  })

  test('no notice is attached unless the option asks for one', async ($, on) => {
    const noticed: string[] = []

    on('ui.notice', ($, e, next) => {
      noticed.push(e.text ?? '')

      return next(e)
    })
    on('agent.spawn', ($, e) => ({ model: e.model ?? 'inherited' }))

    await $.agent.spawn(spawn())

    expect(noticed).toEqual([])
  })
})
