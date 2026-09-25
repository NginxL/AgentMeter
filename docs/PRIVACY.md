# Privacy and data sources

[简体中文](PRIVACY.zh-CN.md) · [README](../README.md)

AgentMeter stores your subscription records on your Mac. It has no project backend, analytics SDK, advertising SDK, or credential export feature. Supported quota adapters contact the relevant provider; a manual update check contacts GitHub.

## Credentials and network access

| Operation | Source and destination | Boundary |
| --- | --- | --- |
| Codex quota | Launch the local `codex app-server`; use `account/read` with `refreshToken: false` and `account/rateLimits/read` | AgentMeter does not read or modify Codex authentication files. The official CLI owns its login, credential storage, token lifecycle, and provider network behavior. |
| Claude quota | Read `claudeAiOauth.accessToken` from `~/.claude/.credentials.json`, or `$CLAUDE_CONFIG_DIR/.credentials.json`; the default profile can fall back to the `Claude Code-credentials` Keychain service | Use the existing token in memory for a GET to `https://api.anthropic.com/api/oauth/usage`. AgentMeter does not refresh tokens or write credentials. A custom configuration directory does not fall back to another profile's default Keychain entry. |
| Manual tracking | User-entered subscription and quota fields, including custom subscriptions and manual fallback for Codex or Claude | No credentials are read and no quota request is sent for a manually tracked entry. |
| Update check | GET `https://api.github.com/repos/NginxL/AgentMeter/releases/latest` | Manual only. No provider credentials or subscription records are attached. If a newer release exists, open the GitHub release page in your browser. |
| Open official dashboard | Open `chatgpt.com/codex/settings/usage` or `claude.ai/settings/usage` in your browser | The browser manages its own login, cookies, and network behavior. AgentMeter does not read browser sessions. |

Claude HTTP sessions disable disk caching and cookies and reject redirects, so a credential is not forwarded to another endpoint.

Background Claude reads prohibit Keychain UI. The explicit Claude connection action can permit the normal macOS authorization prompt. Dismissing or denying access prevents a fresh reading; an older cached reading may remain visible as stale. AgentMeter does not initiate a login, read browser cookies, create AI conversations, or issue model-generation requests.

The official Codex CLI is a separate program. Its own network, authentication, and telemetry settings remain under that program's control; AgentMeter does not override them. Provider endpoints and local credential formats can change, so an adapter may become unavailable until updated.

## Local storage

The packaged app uses the `io.github.nginxl.AgentMeter` UserDefaults domain. Stored data includes:

| Key | Content |
| --- | --- |
| `subscriptions` | Names, provider type, plan labels, manual renewal or expiry dates, monthly amounts, currencies, notes, enabled state, manual-tracking choice, and manual quota windows with recorded-at timestamps |
| `snapshots` | Quota readings, source, available plan information, and fetch timestamps; account identifiers are removed before saving |
| `language` | Interface language; Simplified Chinese by default, switchable to English |
| `autoRefresh` | Whether the 15-minute refresh timer is enabled |

These preferences are local application data, not an encrypted credential vault. Do not put passwords or tokens in free-form notes. AgentMeter does not intentionally write access tokens, raw authentication responses, or credential contents to settings or logs.

Demo data stays in memory and does not replace saved subscription records or quota cache. Demo mode does not invoke the quota providers.

## Refresh and data meaning

Automatic refresh is enabled by default for enabled entries using an automatic source: opening the dashboard triggers a refresh, followed by refreshes every 15 minutes while the app is running. You can turn it off. Ordinary manual refresh actions and the timer share a minimum one-minute interval per provider. The explicit Claude authorization action allows an immediate retry. Entries in manual tracking mode are excluded from these reads.

Saved automatic quota readings are marked stale after relaunch until a successful refresh verifies the current local login. An automatic reading also becomes stale after 30 minutes or a failed refresh. Missing or expired login credentials clear the associated cached reading.

Manual quota readings have their own recorded-at timestamp and a manual source label. The timestamp changes when quota edits are saved; editing only a subscription note or price does not make the quota appear newly recorded. Manual readings do not use the automatic freshness timer, fetch new data, or reset themselves. You can record up to two windows with used percentages and optional reset times. Switching an automatic entry to manual tracking clears its automatic cache and stops future automatic reads for that entry.

The menu bar and dashboard read the same local model; opening the menu does not create a separate credential store or upload quota data. Automatic quota reset timestamps describe the provider's quota window; manual quota reset times are user-entered. Every subscription renewal or expiry date is a manual record in v1. Monthly amounts are also manual; AgentMeter does not access invoices, payment methods, or billing portals.

## Removing local data

Delete individual subscriptions in the app. To remove all AgentMeter preferences and cached quota readings, quit the app and run:

```bash
defaults delete io.github.nginxl.AgentMeter
```

This clears AgentMeter's saved records and settings. It does not sign you out of Codex or Claude Code or delete their credentials. Their official clients manage sign-out and credential removal.

When reporting an issue, share only the relevant error state and reproduction steps. Redact account identifiers, email addresses, private notes, and credentials from any attachment.
