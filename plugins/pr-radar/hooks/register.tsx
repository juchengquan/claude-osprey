import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Pr, Snapshot } from '../types'

const PANE = 'pr-radar'
const TOOL = 'mcp__pr-radar__pr_status'
const POLL_MS = 30_000
const snapshot = atom({ plugin: 'pr-radar', key: 'snapshot' } as const, { prs: [], error: null, at: 0 } as Snapshot, {
  shape: 'snapshot-2',
})

// The filter typed in the pane, matched case-insensitively against any part of
// `owner/name`; '' is every repository. Kept in `$.store` so the next session
// starts with it.
const repo = atom({ plugin: 'pr-radar', key: 'repo' } as const, '', { shape: 'repo-1' })
const REPO_KEY = 'repo'

const matching = (prs: Pr[], filter: string) =>
  filter ? prs.filter(pr => pr.repo.toLowerCase().includes(filter.toLowerCase())) : prs

// Repositories opened under their heading; every other one starts collapsed,
// a repository seen for the first time included. Kept like the filter.
const expanded = atom({ plugin: 'pr-radar', key: 'expanded' } as const, [] as string[], { shape: 'expanded-1' })
const EXPANDED_KEY = 'expanded'

async function toggle($: EngineInterface, name: string) {
  const next = await update($, expanded, list => (list.includes(name) ? list.filter(n => n !== name) : [...list, name]))
  await $.store.set(EXPANDED_KEY, next)
}

// The PRs arrive most recently updated first, so a repository's first
// appearance orders the groups and the busiest one leads.
function byRepo(prs: Pr[]): [string, Pr[]][] {
  const groups = new Map<string, Pr[]>()
  for (const pr of prs) groups.set(pr.repo, [...(groups.get(pr.repo) ?? []), pr])
  return [...groups]
}

function showStatus($: EngineInterface, prs: Pr[], filter: string) {
  const shown = matching(prs, filter)
  const own = shown.filter(p => p.isMine)
  const failing = own.filter(p => p.ci === 'FAILURE' || p.ci === 'ERROR').length
  const toReview = shown.length - own.length
  $.ui.status(
    `PRs${filter ? ` matching ${filter}` : ''}: ${own.length} open${failing ? `, ${failing} failing` : ''}` +
      (toReview ? `, ${toReview} to review` : ''),
  )
}

async function setRepo($: EngineInterface, typed: string) {
  const value = typed.trim()
  await update($, repo, () => value)
  await $.store.set(REPO_KEY, value)
  showStatus($, (await read($, snapshot)).prs, value)
}

// GraphQL search instead of `gh pr list`: that needs a repository, and this
// should show every repository's PRs wherever the session runs. The filter is
// applied here, not in the search: GitHub's `repo:` takes only an exact name.
// Two searches, not one with OR: `(author:@me OR review-requested:@me)` finds
// nothing. Each keeps its 25 most recently updated, filter or not.
const FIELDS = `nodes{...on PullRequest{
  number title url isDraft reviewDecision mergeable updatedAt author{login} repository{nameWithOwner}
  commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}`
const OPEN = 'is:pr is:open archived:false sort:updated-desc'
const QUERY = `query{viewer{login}
  mine:search(query:"${OPEN} author:@me",type:ISSUE,first:25){${FIELDS}}
  asked:search(query:"${OPEN} review-requested:@me",type:ISSUE,first:25){${FIELDS}}}`

type Node = {
  number: number
  title: string
  url: string
  isDraft: boolean
  reviewDecision: Pr['review']
  mergeable: Pr['mergeable']
  updatedAt: string
  author: { login: string } | null
  repository: { nameWithOwner: string }
  commits: { nodes: { commit: { statusCheckRollup: { state: Pr['ci'] } | null } }[] }
}

// The 30-second timer, /prs and the refresh button can overlap; one `gh` at a
// time is enough, and the one running brings the newest list anyway.
let isFetching = false

async function refresh($: EngineInterface) {
  if (isFetching) return
  isFetching = true
  try {
    await fetchPrs($)
  } catch (err) {
    // `$.process.run` rejects rather than answering when the command cannot
    // start or outlives its timeout; uncaught, the pane says "loading…" forever.
    const failure = err instanceof GhFailure ? err : new GhFailure(String(err), 'PRs: gh failed')
    await update($, snapshot, old => ({ ...old, error: failure.message, at: Date.now() }))
    $.ui.status(failure.status)
  } finally {
    isFetching = false
  }
}

class GhFailure extends Error {
  constructor(
    message: string,
    readonly status: string,
  ) {
    super(message)
  }
}

// The GitHub CLI's command is `gh`; some installs name it `gh-cli`. The first
// that starts is kept for the rest of the session.
const GH_COMMANDS = ['gh', 'gh-cli']
const GH_TIMEOUT_MS = 20_000
let ghCommand: string | undefined

async function runGh($: EngineInterface, args: string[]) {
  for (const command of ghCommand ? [ghCommand] : GH_COMMANDS) {
    const started = Date.now()
    try {
      const ran = await $.process.run([command, ...args], { timeoutMs: GH_TIMEOUT_MS })
      ghCommand = command
      return ran
    } catch {
      // Both a missing command and a timeout reject, and only the time tells
      // them apart; a command that ran out its time exists, so trying the next
      // name would only wait twice.
      if (Date.now() - started >= GH_TIMEOUT_MS - 1_000) {
        throw new GhFailure(`GitHub CLI did not answer within ${GH_TIMEOUT_MS / 1000} seconds`, 'PRs: gh timed out')
      }
    }
  }
  ghCommand = undefined
  throw new GhFailure(
    'GitHub CLI not found: install it from https://cli.github.com and run gh auth login',
    'PRs: gh not found',
  )
}

async function fetchPrs($: EngineInterface) {
  const ran = await runGh($, ['api', 'graphql', '-f', `query=${QUERY}`])
  if (ran.exitCode !== 0) {
    const error = ran.stderr.trim().split('\n')[0] || `gh exited ${ran.exitCode}`
    await update($, snapshot, old => ({ ...old, error, at: Date.now() }))
    $.ui.status('PRs: gh failed')
    return
  }
  const { viewer, mine, asked } = JSON.parse(ran.stdout).data as {
    viewer: { login: string }
    mine: { nodes: Node[] }
    asked: { nodes: Node[] }
  }
  const seen = new Set<string>()
  const nodes = [...mine.nodes, ...asked.nodes]
    .filter(n => !seen.has(n.url) && seen.add(n.url))
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
  const prs: Pr[] = nodes.map(n => ({
    repo: n.repository.nameWithOwner,
    number: n.number,
    title: n.title,
    url: n.url,
    isDraft: n.isDraft,
    ci: n.commits.nodes[0]?.commit.statusCheckRollup?.state ?? null,
    review: n.reviewDecision,
    mergeable: n.mergeable,
    // A deleted account's PR has no author.
    author: n.author?.login ?? 'ghost',
    isMine: n.author?.login === viewer.login,
  }))
  await update($, snapshot, () => ({ prs, error: null, at: Date.now() }))
  showStatus($, prs, await read($, repo))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'prs', description: 'Show your open GitHub PRs and the ones waiting for your review',
      // Runs mid-turn instead of waiting for the turn to end: it reads nothing of the turn.
      immediate: true,
      argumentHint: '[part of a repo name]',
    })
    await $.tool.register({
      name: 'pr_status',
      description:
        "The person's open GitHub PRs and the open PRs waiting for their review, as their PR pane last " +
        'fetched them (every 30 seconds; it does not fetch again): repository, number, title, author, CI, ' +
        'review state, merge conflicts. `repo` keeps the repositories whose owner/name contains it, ' +
        "ignoring case; left out, the pane's own filter applies, and '' shows every repository.",
      inputSchema: {
        type: 'object',
        properties: { repo: { type: 'string', description: 'Any part of owner/name' } },
        additionalProperties: false,
      },
      isDeferred: false,
    })
    const stored = await $.store.get(REPO_KEY)
    await update($, repo, () => (typeof stored === 'string' ? stored : ''))
    const opened = await $.store.get(EXPANDED_KEY)
    await update($, expanded, () => (Array.isArray(opened) ? opened.filter(n => typeof n === 'string') : []))
    void refresh($)
    $.clock.every(POLL_MS, () => refresh($))

    return next(e)
  })

  on('command.run', { command: 'prs' }, async ($, e) => {
    await $.ui.open({ id: PANE, title: 'PRs' })
    // `/prs optio` sets the filter as typing it in the field does; a bare /prs
    // keeps the one set, as no word could mean "all" without also being a name.
    const typed = e.args.trim()
    if (typed) await setRepo($, typed)
    // Not awaited: `gh` can take seconds, and the command would hold the prompt
    // until it answered. A timer, because work a hook leaves running may be
    // dropped when the hook returns.
    $.clock.after(0, () => refresh($))
    const filter = typed || (await read($, repo))
    const shown = matching((await read($, snapshot)).prs, filter)

    return { text: `${shown.length} open PRs${filter ? ` matching ${filter}` : ''}; refreshing.` }
  })

  on('tool.call', { tool: TOOL }, async ($, e) => {
    // The model's arguments arrive spread on `e`; it may send any JSON.
    const asked = (e as { repo?: unknown }).repo
    const filter = typeof asked === 'string' ? asked.trim() : await read($, repo)
    const { prs, error, at } = await read($, snapshot)
    const shown = matching(prs, filter).map(({ isMine, ...pr }) => ({ ...pr, waitsForYourReview: !isMine }))
    const text = JSON.stringify({
      filter: filter || null,
      fetchedAt: at ? new Date(at).toISOString() : null,
      error,
      prs: shown,
    })

    return { result: text }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Input, Link } = $.ui.resolve(e)
    const { prs: all, error, at } = await read($, snapshot)
    const filter = await read($, repo)
    const prs = matching(all, filter)
    const open = await read($, expanded)
    const width = e.viewport?.columns ?? 60

    return (
      <Box flexDirection="column">
        <Input
          key="repo"
          label="repo"
          placeholder="part of a repo name"
          value={filter}
          submitLabel="filter"
          onSubmit={typed => setRepo($, typed)}
        />
        <Box flexDirection="row" gap={1}>
          <Text dimColor>{at ? `updated ${new Date(at).toLocaleTimeString([], { hourCycle: 'h23' })}` : 'loading…'}</Text>
          <Button key="refresh" label="refresh" onPress={() => refresh($)}>
            <Text color="cyan">↻</Text>
          </Button>
        </Box>
        {error && <Text color="red">{error}</Text>}
        {at > 0 && prs.length === 0 && !error && <Text dimColor>No open PRs{filter ? ` matching ${filter}` : ''}.</Text>}
        {byRepo(prs).map(([name, group]) => (
          <Box key={name} flexDirection="column" marginTop={1}>
            <Button key={`fold-${name}`} onPress={() => toggle($, name)}>
              <Text bold>
                <Text dimColor>{open.includes(name) ? '▾' : '▸'}</Text> <Text color="blue">{name}</Text>{' '}
                <Text color={groupColor(group)} dimColor={!groupColor(group)}>
                  ({group.length})
                </Text>
              </Text>
            </Button>
            {open.includes(name) && group.map(pr => (
              <Box key={pr.url} flexDirection="column" paddingLeft={2}>
                <Box flexDirection="row" gap={1}>
                  <Link href={pr.url}>
                    <Text bold>#{pr.number}</Text>
                  </Link>
                  <Text wrap="truncate-end">{pr.title.slice(0, Math.max(10, width - 12))}</Text>
                  {/* Copy as well as the link: a link opens only where the terminal
                      draws hyperlinks, which SSH and tmux may not. */}
                  <Button key={`copy-${pr.url}`} label="copy URL" onPress={press => $.ui.copy({ text: pr.url, surface: press.surface })}>
                    <Text dimColor>⧉</Text>
                  </Button>
                </Box>
                <Box flexDirection="row" gap={2} paddingLeft={2}>
                  <Text dimColor={pr.isMine} color={pr.isMine ? undefined : 'cyan'}>
                    by {pr.isMine ? 'you' : pr.author}
                  </Text>
                  <Text color={ciColor(pr.ci)}>CI {ciLabel(pr.ci)}</Text>
                  <Text color={reviewColor(pr)}>{reviewLabel(pr)}</Text>
                  {pr.mergeable === 'CONFLICTING' && <Text color="red">conflicts</Text>}
                </Box>
              </Box>
            ))}
          </Box>
        ))}
      </Box>
    )
  })
}

// A collapsed heading's count says whether anything under it needs a look:
// red for failing CI or conflicts, yellow when one is your move.
const needsFix = (pr: Pr) => pr.ci === 'FAILURE' || pr.ci === 'ERROR' || pr.mergeable === 'CONFLICTING'
const groupColor = (group: Pr[]) =>
  group.some(needsFix) ? 'red' : group.some(pr => reviewColor(pr) === 'yellow') ? 'yellow' : undefined

const ciLabel = (ci: Pr['ci']) =>
  ci === 'SUCCESS' ? '✓ passing' : ci === 'FAILURE' || ci === 'ERROR' ? '✗ failing' : ci ? '● running' : '– none'
const ciColor = (ci: Pr['ci']) =>
  ci === 'SUCCESS' ? 'green' : ci === 'FAILURE' || ci === 'ERROR' ? 'red' : ci ? 'yellow' : 'gray'
const reviewLabel = (pr: Pr) =>
  !pr.isMine ? 'needs your review' : pr.isDraft ? 'draft' : pr.review === 'APPROVED' ? 'approved' : pr.review === 'CHANGES_REQUESTED' ? 'changes requested' : 'awaiting review'
// Yellow is your move (a draft to finish, a review asked of you) and green is
// waiting on others, so "approved", ready to merge, needs a colour of its own.
const reviewColor = (pr: Pr) =>
  !pr.isMine ? 'yellow' : pr.isDraft ? 'yellow' : pr.review === 'APPROVED' ? 'magenta' : pr.review === 'CHANGES_REQUESTED' ? 'red' : 'green'
