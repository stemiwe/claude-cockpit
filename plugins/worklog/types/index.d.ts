export type PanePart = { title: string; lines: string[] }

declare module 'claude-code' {
  interface PluginState {
    worklog: { status: string; question: string; detail: string; todos: string[]; custom: PanePart[] }
  }
}
