import type { On, OpEventResult } from 'claude-code'
import type { Engine } from 'claude-code/testing'
import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'pr-radar',
  component: 'Pane',
  requestId: 'pr-radar',
  props: {
    title: 'PRs',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const pr = (repo: string, number: number, author = 'me', updatedAt = `2026-11-0${number}T00:00:00Z`) => ({
  number,
  title: `PR ${number}`,
  url: `https://github.com/${repo}/pull/${number}`,
  isDraft: false,
  reviewDecision: null,
  mergeable: 'MERGEABLE',
  updatedAt,
  author: { login: author },
  repository: { nameWithOwner: repo },
  commits: { nodes: [{ commit: { statusCheckRollup: { state: 'SUCCESS' } } }] },
})

// Mine and the ones asking for my review come from two searches; the review
// request is the newest, so it must lead its group although it came second.
const GH = JSON.stringify({
  data: {
    viewer: { login: 'me' },
    mine: { nodes: [pr('acme/widgets', 1), pr('acme/gadgets', 2)] },
    asked: { nodes: [pr('acme/widgets', 3, 'alice')] },
  },
})

const ANSWERED: OpEventResult<'process.run'> = {
  value: { exitCode: 0, stdout: GH, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
}

const copied: string[] = []

function engine(
  on: On,
  gh: (argv: readonly string[]) => OpEventResult<'process.run'> | Promise<OpEventResult<'process.run'>> = () => ANSWERED,
  saved: (key: string, value: unknown) => void = () => {},
) {
  on('command.register', () => ({ value: { command: 'prs' } }))
  on('tool.register', () => ({ value: { tool: 'mcp__pr-radar__pr_status' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.copy', (_, e) => {
    copied.push(e.text)
    return { value: { isCopied: true } }
  })
  on('store.get', () => ({ value: undefined }))
  on('store.set', (_, e) => {
    saved(e.key, e.value)
    return { value: undefined }
  })
  on('process.run', (_, e) => gh(e.argv))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
}

test('the tool answers what the pane fetched, narrowed by a part of the name', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ran = await $.tool.call({ tool: 'mcp__pr-radar__pr_status', repo: 'GADG' })
  const answer = JSON.parse(String(ran.result))
  expect(answer.prs.map((pr: { number: number }) => pr.number)).toEqual([2])
  expect(answer.fetchedAt).not.toBeNull()

  const all = JSON.parse(String((await $.tool.call({ tool: 'mcp__pr-radar__pr_status' })).result))
  expect(all.prs.map((pr: { number: number; waitsForYourReview: boolean }) => [pr.number, pr.waitsForYourReview]))
    .toEqual([[3, true], [2, false], [1, false]])
})

test('PRs group under one heading per repository, collapsed until opened, and a part of the name in any case keeps only its repositories', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Input', key: 'repo' })).toBeTruthy()
    // Interleaved in the fixture, so a group per PR would draw the heading twice.
    const headings = await ui.findAll({ type: 'Text', text: /^. acme\/widgets/ })
    expect(headings.map(h => h.text)).toEqual(['▸ acme/widgets (2)'])

    // Every repository starts collapsed; opening one shows its PRs alone.
    expect(await ui.find({ type: 'Text', text: 'PR 1' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'PR 2' })).toBeUndefined()
    await ui.press({ key: 'fold-acme/widgets' })
    expect(await ui.find({ type: 'Text', text: /^▾ acme\/widgets \(2\)/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'PR 1' })).toBeTruthy()
    // The number opens the PR's address and the trailing ⧉ copies it: both
    // must be that PR's own, or a press lands on another PR.
    const url = 'https://github.com/acme/widgets/pull/1'
    await ui.press({ key: `copy-${url}` })
    expect(copied.at(-1)).toBe(url)
    const link = await ui.find({ type: 'Link', text: '#1' })
    expect(link?.props).toMatchObject({ href: url })
    const authors = await ui.findAll({ type: 'Text', text: /^by / })
    expect(authors.map(a => a.text)).toEqual(['by alice', 'by you'])
    expect(await ui.find({ type: 'Text', text: 'needs your review' })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: 'PR 2' })).toBeUndefined()
    await ui.press({ key: 'fold-acme/widgets' })
    expect(await ui.find({ type: 'Text', text: 'PR 1' })).toBeUndefined()

    await ui.input({ key: 'repo', text: 'WIDG' })
    expect(await ui.find({ type: 'Text', text: /widgets/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /gadgets/ })).toBeUndefined()

    await ui.input({ key: 'repo', text: '' })
    expect(await ui.find({ type: 'Text', text: /gadgets/ })).toBeTruthy()
    await ui.unmount()
  }
})

test('/prs answers while gh still runs, so the prompt is not held for the fetch', async ($, on) => {
  // The session's first fetch answers; every later `gh` is held until the test
  // lets it go: a /prs that waits on it never answers in time. Let go at the
  // end, so nothing is left running past the test.
  let calls = 0
  let release: (answer: OpEventResult<'process.run'>) => void = () => {}
  engine(on, () => (++calls === 1 ? ANSWERED : new Promise(resolve => (release = resolve))))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ran = await Promise.race([
    $.command.run({ command: 'prs', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 120 } }),
    // The kit's clock is mocked; a real two seconds is what a person would wait.
    new Promise(resolve => (globalThis as { setTimeout?: (f: () => void, ms: number) => void }).setTimeout?.(() => resolve('held'), 2000)),
  ])
  release(ANSWERED)
  expect(ran).toMatchObject({ text: '3 open PRs; refreshing.' })
})

test('/prs with a part of a name sets the pane filter, and a bare /prs keeps it', async ($, on) => {
  let saved: unknown
  engine(on, undefined, (key, value) => {
    if (key === 'repo') saved = value
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const prs = (args: string) =>
    $.command.run({ command: 'prs', args, origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 120 } })

  expect((await prs(' WIDG ')).text).toBe('2 open PRs matching WIDG; refreshing.')
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /acme\/widgets/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /acme\/gadgets/ })).toBeUndefined()
  // Kept as the field's filter is, so the next session opens the same way.
  expect(saved).toBe('WIDG')

  expect((await prs('')).text).toBe('2 open PRs matching WIDG; refreshing.')
  await ui.unmount()
})

// What a command that cannot start does to `$.process.run`: the call rejects.
const MISSING: OpEventResult<'process.run'> = { deny: 'spawn ENOENT' }

// A rejected call settles after session.start has returned, so the first fetch
// is waited for through the tool before the pane is drawn; a pane drawn sooner
// shows "loading…" whatever the fetch ends in.
async function firstFetch($: Engine) {
  for (let tries = 0; tries < 100; tries++) {
    const answer = JSON.parse(String((await $.tool.call({ tool: 'mcp__pr-radar__pr_status', repo: '' })).result))
    if (answer.fetchedAt) return answer
  }
  throw new Error('the first fetch never finished')
}

test('with no GitHub CLI the pane says how to get one, where it used to say "loading…" forever', async ($, on) => {
  const tried: string[] = []
  engine(on, argv => {
    tried.push(argv[0] ?? '')
    return MISSING
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await firstFetch($)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^GitHub CLI not found: install it from https:\/\/cli.github.com/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: 'loading…' })).toBeUndefined()
  expect(tried.slice(0, 2)).toEqual(['gh', 'gh-cli'])
  await ui.unmount()
})

test('a GitHub CLI installed as gh-cli is used when gh is not there', async ($, on) => {
  engine(on, argv => (argv[0] === 'gh-cli' ? ANSWERED : MISSING))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await firstFetch($)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /acme\/widgets/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /GitHub CLI not found/ })).toBeUndefined()
  await ui.unmount()
})
