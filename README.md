# HyprMux

A macOS terminal that behaves like a maximized [Hyprland](https://hypr.land) desktop:
a waybar-style top bar, a Touch-Bar-style project dock along the bottom, dwindle
tiling, numbered / named / sub-workspaces, wallpapers, remote (ssh + tmux)
terminals, live status icons for coding agents, and a browser pane. **Super is
Cmd.** There is no sidebar and there are no per-pane tabs.

HyprMux is a fork of [cmux](https://github.com/manaflow-ai/cmux) (Ghostty
terminals, the bonsplit pane library). The upstream README is kept as
[`README.cmux.md`](README.cmux.md). License: GPL-3.0-or-later, as upstream.

```
┌ 1  2  work.1  work.2 ───────── title ─────── ◉ ◉ ● 🔔 🎨 +  Fri 17 Oct 11:23 ┐   top bar
│ ┌──────────────┬───────────────┐                                              │
│ │              │               │   terminals tile like Hyprland's dwindle     │
│ │              ├───────┬───────┤   layout, over your wallpaper                │
│ └──────────────┴───────┴───────┘                                              │
├ [alpha] [beta] [gamma] [delta] …                         dock (layers)       ┤   bottom bar
└──────────────────────────────────────────────────────────────────────────────┘
```

## Contents

- [Build and run](#build-and-run)
- [Configuration at a glance](#configuration-at-a-glance)
- [`bar.toml` reference](#bartoml-reference)
- [`fleet` reference](#fleet-reference)
- [Agent status icons](#agent-status-icons)
- [Themes, wallpapers, icons](#themes-wallpapers-icons)
- [Keybindings](#keybindings)
- [For AI agents: customizing a user's bars](#for-ai-agents-customizing-a-users-bars)

## Build and run

Requirements: macOS, Xcode, `zig` 0.16 (`brew install zig@0.16`, then put
`/opt/homebrew/opt/zig@0.16/bin` on `PATH`).

```bash
./scripts/setup.sh                      # one time: submodules, GhosttyKit
CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag mine   # build a tagged dev app
scripts/hyprmux-install.sh mine         # copy it to ~/Applications/HyprMux.app
open ~/Applications/HyprMux.app
```

After every rebuild run `reload.sh` **and** `hyprmux-install.sh`; otherwise the
installed app is a stale copy. The shell lives in `Sources/AgenticShell.swift`.

## Configuration at a glance

HyprMux reads plain files in your home directory. Nothing is required: with no
files it shows placeholder projects (`alpha` … `lambda`) and runs local shells.

| File | Purpose | Read |
|---|---|---|
| `~/.config/agentic-laptop/bar.toml` | Dock buttons: projects, customers, tool buttons, machines | at launch (restart to apply) |
| `~/.config/agentic-laptop/icons/<name>.svg\|png` | Button / agent icons | at launch |
| `~/.config/claude-badged/fleet` | Hosts: where terminals attach, which hosts report agent status | at launch |
| `~/.claude-badges.log` (on each machine) | Agent events: `<session> busy\|ask\|done` | live |
| `~/.config/ghostty/config` | Terminal theme (written by the theme picker) | live |
| `~/Pictures/wallpapers/*.{png,jpg,jpeg,webp,heic}` | Wallpaper library | on cycle |

The directory name `agentic-laptop` is historical: HyprMux uses the same
profile as the Linux (Hyprland + waybar + Touch Bar) setup, so one profile
drives both.

## `bar.toml` reference

HyprMux does **not** use a full TOML parser. It reads the file **line by line**,
so follow these rules exactly:

1. A list starts on its own line as `Name = [` and ends with a line that begins with `]`.
2. **One button per line**, written as an inline table that starts with `{`:
   `{ Text = "alpha", Action = [ "LeftMeta", "LeftShift", "O" ], Color = "blue", Badge = "alpha", Icon = "alpha" },`
3. Values are **double-quoted** strings. Single quotes and multi-line values are not read.
4. Lines starting with `#` and blank lines are ignored. Keys it does not know are ignored.
5. Only these lists are read; everything else in the file (Linux Touch Bar settings,
   `[Palette]`, `[ExtraLayers]` headers, …) is skipped, so a profile shared with
   Linux works unchanged.

### Lists

| List | Becomes | Chord |
|---|---|---|
| `PrimaryLayerKeys` | First dock layer: **projects** (buttons with `Badge`) and **tool buttons** (buttons with `Exec`) | `Cmd+Shift+<key>` |
| `MediaLayerKeys` | Second dock layer: **customers** (buttons with `Badge`). Same shape as projects | `Cmd+Shift+<key>` |
| `machines` | Third dock layer: ssh machines | `Cmd+Option+1…9`, in file order |

### Button keys

| Key | Used by | Meaning |
|---|---|---|
| `Text` | all (**required**: lines without it are skipped) | Label on the button |
| `Action` | projects, customers, tools | A list of quoted strings; **only the last one is used**, as the chord letter. `[ "LeftMeta", "LeftShift", "O" ]` means `Cmd+Shift+O` on macOS. The modifiers in the list are ignored here (they matter on Linux) |
| `Badge` | projects, customers | The workspace name this button opens (`Badge = "alpha"` opens workspace `alpha.1`). Also the name agent status icons match |
| `Color` | all | `blue` `mauve` `peach` `green` `red` `teal` `yellow`; anything else (e.g. `surface`) is neutral |
| `Icon` | all | File stem in `icons/` (`icons/alpha.svg` or `.png`). Without it the `Text` label is shown |
| `Exec` | tool buttons | Shell command to run; `$HOME` is expanded. A button with `Exec` and no `Badge` is a tool button |
| `Workspace` | machines | Workspace name (default: `Text`) |
| `Host` | machines | ssh target, `user@host` or an alias from `~/.ssh/config` |

A **project** = a button with `Badge` and an `Action`. Opening it creates workspace
`<Badge>.1` containing three terminals tiled Hyprland-style, attached to tmux
sessions `<Badge>`, `<Badge>1` and `<Badge>2` (on the first host of the `fleet`
file, or locally if none). Opening it again just focuses it.

### Minimal example

```toml
PrimaryLayerKeys = [
    { Text = "api",    Action = [ "LeftMeta", "LeftShift", "A" ], Color = "blue",  Badge = "api",    Icon = "api" },
    { Text = "web",    Action = [ "LeftMeta", "LeftShift", "W" ], Color = "mauve", Badge = "web" },
    { Text = "notes",  Exec = "$HOME/.local/bin/open-notes",      Action = [ "LeftMeta", "LeftShift", "N" ] },
]

MediaLayerKeys = [
    { Text = "acme",   Action = [ "LeftMeta", "LeftShift", "C" ], Color = "yellow", Badge = "acme" },
]

machines = [
    { Text = "server1", Workspace = "server1", Host = "me@server1", Color = "blue" },
    { Text = "server2", Workspace = "server2", Host = "server2",    Color = "green" },
]
```

### Chords that are already taken

`Cmd+Shift+` with `B A Y X P` (browser apps), `-`, `=`, `Return`, `Space` are built in
(see [Keybindings](#keybindings)). Do not assign those letters to projects, and keep
each letter unique across `PrimaryLayerKeys` and `MediaLayerKeys`: with duplicates the
first match wins.

## `fleet` reference

`~/.config/claude-badged/fleet`: one ssh target per line.

```
me@server1
me@server2
```

- The **first line** is where project terminals attach: `ssh -t <host> "tmux new -A -s '<session>' \; set -s escape-time 0"`.
  The `AGENTIC_REMOTE` environment variable overrides it. With no file, terminals run local tmux.
- **Every host** is followed for [agent status](#agent-status-icons).
- ssh must work non-interactively (`ssh -o BatchMode=yes <host> true` must succeed): use keys.

## Agent status icons

The top bar shows one icon per coding agent (up to 8), left of the bell:

| Look | Meaning |
|---|---|
| spinner on the icon | the agent is working |
| green dot | it finished |
| pink dot | it is asking you something |

Clicking an icon jumps to that agent's workspace; a finished agent then leaves the
bar (a working one stays). A `busy` older than 30 minutes is dropped.

**The contract**: each machine where agents run appends one line per event to
`~/.claude-badges.log`:

```
<tmux-session> busy
<tmux-session> ask
<tmux-session> done
```

HyprMux runs `tail -F` on the local log and, over ssh, on each `fleet` host. Only
events that arrive after launch are shown. The session name maps to a project by
stripping everything after a `.` and trailing digits: `api`, `api1`, `api2` and
`api.1` all belong to `Badge = "api"`, and the icon is that project's `Icon` (or its
first letter on its `Color`).

Wire the log to your agent's hooks. For example, for an agent running inside tmux
(adapt to your tool's hook mechanism):

```bash
# on "agent started working" / "tool used":
echo "$(tmux display-message -p '#S') busy" >> ~/.claude-badges.log
# on "needs input / permission":
echo "$(tmux display-message -p '#S') ask"  >> ~/.claude-badges.log
# on "finished":
echo "$(tmux display-message -p '#S') done" >> ~/.claude-badges.log
```

## Themes, wallpapers, icons

- **Terminal theme**: the palette button in the top bar offers Catppuccin Mocha, Tokyo
  Night, Gruvbox Dark, Dracula, Nord and Rose Pine. The choice is written to
  `~/.config/ghostty/config` as one `theme = …` line. Terminal colors never follow the
  OS light/dark setting. To use another [Ghostty theme](https://ghostty.org/docs/features/theme)
  or any other Ghostty option, edit that file (reload with the app menu's *Reload
  Configuration*); the picker only rewrites it when you pick from the menu.
- **Wallpapers**: drop images in `~/Pictures/wallpapers`. `Cmd+Ctrl+Space` cycles
  forward, `+Option` backward, `+Shift` random. Without images a gradient is used.
- **Icons**: `~/.config/agentic-laptop/icons/<name>.svg` or `.png`, referenced from
  `bar.toml` by stem (`Icon = "name"`). Square, transparent background, ~64px or SVG.

## Keybindings

Super = Cmd. Workspaces are numbered (`1`…`9`, created on demand), named
(`project.1`) or sub-workspaces (`project.2`, …). An empty workspace closes when you leave it.

| Keys | Action |
|---|---|
| `Cmd+1…9` | Go to / create numbered workspace |
| `Cmd+Shift+<letter>` | Open project or customer (from `bar.toml`) |
| `Cmd+[` / `Cmd+]` | Previous / next sub-workspace (`]` creates a new one) |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous workspace |
| `Cmd+Ctrl+Tab`, `Cmd+Option+←/→` | Previously visited workspace, history back / forward |
| `Cmd+Return` | New terminal, split Hyprland-dwindle style |
| `Cmd+←↑↓→` | Focus pane |
| `Cmd+-` / `Cmd+=` | Resize left / right |
| `Cmd+Shift+-` / `Cmd+Shift+=` | Resize up / down |
| `Cmd+W` | Close focused pane |
| `Cmd+F` | Zoom focused pane |
| `Cmd+N` | Jump to the workspace needing attention |
| `Cmd+Option+1…9` | Open machine from `machines` |
| `Cmd+Ctrl+↑↓←→`, `Cmd+Ctrl+Return` | Dock: change layer, move selection, activate |
| `Cmd+Ctrl+Space` (+`Option` / +`Shift`) | Next / previous / random wallpaper |
| `Cmd+Shift+Space` | Toggle the top bar |
| `Cmd+Shift+B / A / Y / X / P` | Browser pane: web / ChatGPT / YouTube / X / Photos |
| `Cmd+Shift+Return` | Browser pane on a search page |

## For AI agents: customizing a user's bars

**Users: point your coding agent at this README** (for example: *"Read the README of
HyprMux and customize my bars: add a project for each repo in ~/code, …"*).

Everything customizable is a text file under your home directory; you never need to
edit or rebuild the app. Follow this procedure:

1. **Inspect the current state** before changing anything:
   `cat ~/.config/agentic-laptop/bar.toml ~/.config/claude-badged/fleet`,
   `ls ~/.config/agentic-laptop/icons ~/Pictures/wallpapers`. If a file is a symlink
   (a shared profile repo), edit the link target and tell the user.
2. **Back up** `bar.toml` (`cp bar.toml bar.toml.bak`) so the change can be reverted.
3. **Edit using the exact line format** in [`bar.toml` reference](#bartoml-reference):
   one `{ … }` button per line, double-quoted values, a unique `Cmd+Shift` letter per
   project. Prefer appending one line per new project or machine and keeping the
   existing ones.
4. **Check the invariants** after editing: every list still opens with `Name = [` and
   closes with a line starting `]`; every button line has `Text`; each project line
   has both `Badge` and `Action`; no chord letter is duplicated or one of
   `B A Y X P`; every `Icon = "x"` has an `icons/x.svg` or `icons/x.png`; every
   `Color` is one of the seven names.
5. **Tell the user to restart HyprMux** (`bar.toml`, icons and `fleet` are read at
   launch). Theme and wallpaper changes apply live.
6. **Do not** put secrets in these files, and do not change a host in `fleet` or
   `machines` without being told the exact `user@host`: the first `fleet` line is
   where every new terminal will ssh.

Common tasks:

| The user asks for | Do |
|---|---|
| "A project/button for repo X" | Append a `PrimaryLayerKeys` line with `Badge = "X"` and a free letter |
| "A customer / second row" | Same, in `MediaLayerKeys` |
| "Add a machine" | Append a `machines` line (`Text`, `Workspace`, `Host`); it gets the next `Cmd+Option+N` |
| "A button that runs a script" | `PrimaryLayerKeys` line with `Exec` and no `Badge` |
| "Icons" | Save square SVG/PNG files in `icons/`, set `Icon = "<stem>"` |
| "Agent status for my servers" | Add hosts to `fleet`; ensure agents there append to `~/.claude-badges.log` |
| "Change colors / theme" | Edit `theme = …` in `~/.config/ghostty/config` (any Ghostty theme name) |
| "New wallpapers" | Put image files in `~/Pictures/wallpapers` |

Changing the *look* of the bars themselves (layout, new widgets, new keybinds) is a
source change: edit `Sources/AgenticShell.swift` (top bar `AgenticTopBar`, dock
`AgenticDock`/`AgenticBottomBar`, keybinds `AgenticKeymap.handle`), rebuild as in
[Build and run](#build-and-run), and run `scripts/hyprmux-install.sh`.

## Credits

Built on [cmux](https://github.com/manaflow-ai/cmux) and
[Ghostty](https://ghostty.org). Hyprland / waybar / Touch Bar behavior follows the
`agentic-laptop` Linux setup.
