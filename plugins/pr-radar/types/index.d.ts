export type Pr = {
  repo: string
  number: number
  title: string
  url: string
  isDraft: boolean
  ci: 'SUCCESS' | 'FAILURE' | 'ERROR' | 'PENDING' | 'EXPECTED' | null
  review: 'APPROVED' | 'CHANGES_REQUESTED' | 'REVIEW_REQUIRED' | null
  mergeable: 'MERGEABLE' | 'CONFLICTING' | 'UNKNOWN'
  author: string
  isMine: boolean
}

export type Snapshot = { prs: Pr[]; error: string | null; at: number }

declare module 'claude-code' {
  // The mod's own tool, which the generated MCP types list only once it has
  // loaded; the same shape as theirs, so the two declarations merge.
  interface McpToolInputs {
    'mcp__pr-radar__pr_status': { repo?: string }
  }
  interface PluginState {
    'pr-radar': { snapshot: Shaped<Snapshot>; repo: Shaped<string>; expanded: Shaped<string[]> }
  }
}
