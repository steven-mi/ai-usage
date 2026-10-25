# AI Usage

AI Usage is a small macOS menu bar app that shows current Codex, Claude Code, Antigravity, Cursor, and Grok Bot usage limits and reset times.

## Requirements

- macOS 13 or later on Apple silicon
- Swift compiler (included with Xcode Command Line Tools)
- Codex CLI signed in for Codex usage
- Claude Code signed in with a Claude subscription for Claude usage
- Antigravity signed in for Antigravity usage

## Build and run

From the repository folder, run:

```sh
./build.sh --open
```

This builds `dist/AI Usage.app`. If AI Usage is already running, the script replaces the old process and opens the rebuilt app; otherwise use `--open` to launch it. You can also open the app from Finder. To launch AI Usage when you log in, add it under **System Settings → General → Login Items**.

## Using the menu bar app

- The menu bar item shows usage values only for providers that returned data; unavailable providers are omitted.
- Select it to see the usage windows and their reset times.
- Usage refreshes when the app starts and every minute. Select **Refresh** in the popover to update it sooner.
- If a provider is signed out or its usage service is unavailable, the popover shows a status message.
- Antigravity shows the quota for each model returned by the signed-in desktop app. Models that share the same quota window are shown once.
- On unified X Subscription accounts, Cursor and Grok Bot show the same shared weekly usage percentage. On other accounts, the app shows Cursor usage and leaves Grok Bot as `—` because their usage may be separate; dashboard links remain available.

Eligible X Subscription accounts share one weekly pool across Cursor and Grok Bot. Legacy Cursor plans have monthly pools, so the app only repeats Cursor's percentage for accounts reported as unified. See [Cursor's usage guide](https://cursor.com/help/models-and-usage/usage-limits) and [xAI's X Subscription usage guide](https://docs.x.ai/x-subscription/usage-limits).

## Credentials and privacy

AI Usage reads existing local sign-in credentials. It reads the Codex OAuth token and account ID from `~/.codex/auth.json`, Antigravity's access token from its local `state.vscdb`, Cursor's access token and machine ID from its local `state.vscdb`, and Claude Code's OAuth token from macOS Keychain, `~/.claude/.credentials.json`, or the `CLAUDE_CODE_OAUTH_TOKEN` environment variable. It sends credentials directly to the respective usage service and does not save a separate copy.

Claude subscription usage requires Claude Code OAuth sign-in; API key billing does not provide the same usage limits. Antigravity and Cursor/Grok usage use the same app services as their installed clients. These are not documented public APIs, so changes, expired credentials, or rate limits may temporarily make usage unavailable. Reopen the relevant app to refresh its local sign-in if this happens.
