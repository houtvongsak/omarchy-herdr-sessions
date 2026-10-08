# Herdr Session Manager for Omarchy

Pick, open, and manage your [herdr](https://herdr.dev) sessions, on this computer and your other machines.

![Herdr Session Manager](preview.png)

Requires herdr (ships with Omarchy).

---

### Step 1: Install

```bash
omarchy plugin add https://github.com/houtvongsak/omarchy-herdr-sessions.git --enable
```

---

### Step 2: Add Shortcut

Run this to bind **`Super + Ctrl + Enter`**:

```bash
cat << 'EOF' >> ~/.config/hypr/bindings.lua

-- Herdr Session Picker
hl.unbind("SUPER + CTRL + RETURN")
o.bind("SUPER + CTRL + RETURN", "Herdr Session Manager", "omarchy-shell shell toggle io.github.houtvongsak.herdr-sessions")
EOF
hyprctl reload
```

---

### Step 3: Use It

Press **`Super + Ctrl + Enter`**. The first time, pick your keys: **Default** (type to search) or **Vim** (`hjkl`, `/` to search).

| Default | Vim | Action |
|---|---|---|
| type | `/` | Search |
| `↑` `↓` | `k` `j` | Move |
| `Tab` / `Shift+Tab` | `l` / `h` | Next / previous machine |
| `Enter` | `Enter` | Open (a stopped session starts again) |
| `Ctrl+N` | `n` | New session |
| `Ctrl+S` | `s` | Stop |
| `Ctrl+D` | `d` | Delete a stopped session |
| `Ctrl+A` / `Ctrl+X` | `a` / `x` | Add / remove a machine |
| `Ctrl+K` | `Ctrl+K` | Switch Default ↔ Vim |
| `Esc` | `Esc` | Clear search, then close |

A session lit and marked **open here** already has a herdr window on this computer.

---

### Your Keys

Click **keys:** in the picker to open `~/.config/herdr-sessions/keys.json`. It lists every action with its keys; copy one into `keys`, change it, save. It applies at once.

```json
{
  "preset": "vim",
  "keys": { "stop": ["s", "f2"] }
}
```

Keys can be letters, digits, symbols, arrows, `f1`–`f12`, with `ctrl+` `alt+` `shift+`. The footer warns about keys that clash.

---

### Other Machines

Each machine gets its own tab. Add one with `Ctrl+A` (or `a`), or list them in `~/.config/herdr-sessions/machines`, one per line:

```
you@buildbox
ssh://you@server:2222
```

Machines saved with `herdr machine add` show up too. Each needs herdr and SSH without a password prompt (a key). Tabs show each machine's herdr version and flag one that differs from yours; keep versions the same for opening to work.

---

### Update

```bash
omarchy plugin update io.github.houtvongsak.herdr-sessions
omarchy-restart-shell
```

The restart makes Omarchy load the new version.

---

### Removal

Remove the plugin and restore the original `Super + Ctrl + Enter`:

```bash
omarchy plugin remove io.github.houtvongsak.herdr-sessions
sed -i '/^-- Herdr Session Picker$/,/herdr-sessions")$/d' ~/.config/hypr/bindings.lua
hyprctl reload
```

### License

MIT
