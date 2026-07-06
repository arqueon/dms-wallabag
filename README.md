# DMS-Wallabag

[Wallabag](https://wallabag.org) plugin for [DankMaterialShell](https://danklinux.com): your
read-it-later queue in the DankBar.

- Bar pill with the wallabag logo and an unread counter (polled in the background).
- Popout with your entries: source domain, reading time, age, preview thumbnail.
- Click a title (or the open icon, or middle-click the row) to open it in the browser
  **without closing the popout** — open as many as you want.
- Expand a row to see a minimal excerpt of the extracted content, its tags and origin.
- Row actions: mark read/unread (archive), star/unstar, delete (two-step confirm),
  re-fetch content, copy URL.
- Filters (Unread / Starred / Archive / All), server-side search, quick-add a URL.
- Right-click the bar pill to refresh.

## Requirements

- `curl` and `secret-tool` (libsecret) on `PATH`.
- A Wallabag ≥ 2.4 instance and an API client (`Settings → API clients management`
  a.k.a. `/developer` on your instance).

## Setup

1. Symlink or copy this directory to `~/.config/DankMaterialShell/plugins/wallabag`,
   then Settings → Plugins → Scan for Plugins → enable **DMS-Wallabag** and add it to a bar section.
2. In the plugin settings fill in: instance URL, client ID, username.
3. Enter the client secret and your password in the *Credenciales secretas* section —
   they are stored in the system keyring (`secret-tool`, service `dms-wallabag`),
   never in plain text. Equivalent CLI:

   ```sh
   secret-tool store --label='DMS Wallabag client_secret' service dms-wallabag key client_secret
   secret-tool store --label='DMS Wallabag password' service dms-wallabag key password
   ```

Auth uses the OAuth2 password grant with automatic refresh; tokens live only in memory.

## Licensing

Plugin code: GPL-3.0-or-later. The wallabag logo (`Images/wallabag.svg`) is from
[wallabag/logo](https://github.com/wallabag/logo), design by Maylis Agniel,
licensed under the Free Art License 1.3.
