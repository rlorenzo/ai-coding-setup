import { describe, expect, test } from 'claude-code/testing'

import Options from '../hooks/options'

// A test cannot vary the options the mod under test loads with -- the kit
// loads an inline plugin's register as a standalone module, so it cannot call
// into the mod -- so the option reading is covered here, directly, and
// register.test.ts covers the hook under the manifest's defaults.
describe('options', () => {
  test('an unset model reads as haiku', () => {
    expect(Options.modelOf({})).toBe('haiku')
  })

  test('a model is taken as given, trimmed', () => {
    expect(Options.modelOf({ model: '  sonnet ' })).toBe('sonnet')
  })

  // A blank value is unset, not "pin the empty string".
  test('a blank model falls back rather than pinning nothing', () => {
    expect(Options.modelOf({ model: '   ' })).toBe('haiku')
  })

  test('inherit is the one model that registers no hook', () => {
    expect(Options.isInherited({ model: 'inherit' })).toBe(true)
    expect(Options.isInherited({ model: 'haiku' })).toBe(false)
    expect(Options.isInherited({})).toBe(false)
  })

  test('unset agents read as Explore alone', () => {
    expect(Options.agentsOf({})).toEqual(['Explore'])
  })

  test('agents given as a list are taken as given', () => {
    expect(Options.agentsOf({ agents: ['Explore', 'Recon'] })).toEqual([
      'Explore',
      'Recon',
    ])
  })

  // A `multiple` option is an array in the manifest, but a single
  // `--config agents=...` pass arrives as one bare string.
  test('agents given as one comma-separated string split into names', () => {
    expect(Options.agentsOf({ agents: 'Explore, Recon' })).toEqual([
      'Explore',
      'Recon',
    ])
  })

  test('blank entries are dropped, and an all-blank list falls back', () => {
    expect(Options.agentsOf({ agents: 'Explore, ,Recon' })).toEqual([
      'Explore',
      'Recon',
    ])
    expect(Options.agentsOf({ agents: [' ', ''] })).toEqual(['Explore'])
  })

  test('the notice is off unless asked for', () => {
    expect(Options.isAnnounced({})).toBe(false)
    expect(Options.isAnnounced({ notice: false })).toBe(false)
    expect(Options.isAnnounced({ notice: true })).toBe(true)
  })
})
