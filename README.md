# Herdr Session Manager for Omarchy

Interactive session picker, launcher, and manager for [Herdr](https://herdr.dev) AI coding agent sessions.

![Herdr Session Manager](preview.png)

Requires [herdr](https://herdr.dev) (ships with Omarchy).

---

### Step 1: Install

```bash
omarchy plugin add https://github.com/houtvongsak/omarchy-herdr-sessions.git --enable
```

---

### Step 2: Add Shortcut

Run this command in your terminal to bind **`Super + Ctrl + Enter`**:

```bash
cat << 'EOF' >> ~/.config/hypr/bindings.lua

-- Herdr Session Picker
hl.unbind("SUPER + CTRL + RETURN")
o.bind("SUPER + CTRL + RETURN", "Herdr Session Manager", "omarchy-shell shell toggle io.github.houtvongsak.herdr-sessions")
EOF
hyprctl reload
```

*(Or edit manually with `nano ~/.config/hypr/bindings.lua` and run `hyprctl reload`).*

---

### Step 3: Use It

Press **`Super + Ctrl + Enter`**. Each machine has a tab, this computer first, named by host name as herdr shows it. Every herdr session on it is listed, running or stopped. A session that a herdr window on this computer is showing is lit and marked **open here**; the rest are dimmer.

| Key | Action |
|---|---|
| `h` / `l` (or `←` / `→`, `Tab`) | Previous / next machine |
| `j` / `k` (or `↓` / `↑`) | Next / previous session |
| `Enter` | Open the session (a stopped one starts again) |
| `/` | Search this machine's sessions; `Esc` leaves the search |
| `n` | New session on this machine |
| `s` | Stop the session |
| `d` / `Delete` | Delete a stopped session |
| `a` / `x` | Add a machine / remove this machine's tab |
| `r` | Refresh |
| `h` `j` `k` `l` (in a confirm box) | Move between Cancel and Delete / Remove |
| `Esc` | Close |

---

### Other Machines

The picker looks for sessions on every machine in `~/.config/herdr-sessions/machines`, one SSH target per line (`user@host` or a `Host` from `~/.ssh/config`), plus any machine saved with `herdr machine add`:

```
# ~/.config/herdr-sessions/machines
you@buildbox
desktop
```

- `a` in the picker adds a line; `x` removes the current machine's.
- This computer is skipped, so one list can be shared by all your machines.
- Each machine needs SSH that doesn't prompt (a key or agent) and herdr; `~/.local/bin`, where herdr installs itself, is searched.
- Sessions are read with `herdr session list --json` over SSH, all machines at once. Opening one runs `herdr --remote <target> [--session <name>]` in a terminal; stop and delete run `herdr session stop|delete` over SSH.

---

### Removal

Remove the plugin and restore the original `Super + Ctrl + Enter` (opens default herdr):

```bash
omarchy plugin remove io.github.houtvongsak.herdr-sessions
sed -i '/^-- Herdr Session Picker$/,/herdr-sessions")$/d' ~/.config/hypr/bindings.lua
hyprctl reload
```

### License

MIT
