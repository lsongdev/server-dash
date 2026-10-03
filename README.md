# ServerDash

A focused iPhone/iPad app for managing Linux servers, checking their health, and opening fast SSH terminal sessions.

Server Dash intentionally keeps the product small:

- keep a list of servers and SSH credentials
- show CPU, memory, filesystem, network, load, uptime, and system information
- keep optional status history
- open multiple persistent SSH terminal sessions
- protect the app or terminal access with device authentication

## Terminal

The terminal stack has two clear responsibilities:

```
SSH transport (NMSSH)
        │ raw bytes / PTY resize
        ▼
Terminal emulator + UI (GhosttyTerminal)
```

NMSSH owns the SSH connection and PTY. [Ghostty](https://ghostty.org/) owns terminal emulation, rendering, input, selection, clipboard, scrollback, keyboard handling, and the iOS terminal accessory bar.

Terminal sessions stay alive while navigating around the app. Returning to a session restores its terminal state and scrollback.

SSH shells send protocol keepalives after 30 seconds of idle time while the app can run. On entering the background, the app requests a finite iOS execution grace period; expiration stops maintenance without deliberately closing SSH. iOS can still suspend the app, and network changes or server timeouts can break the connection.

Returning to the foreground checks each existing connection with a temporary SSH channel, without executing a command or writing into the shell. A check gets 15 seconds of active execution time to receive a server response. Disconnected sessions retain their output and offer manual reconnection, which opens a new shell and does not replay input. Use a remote `tmux` session when commands and the working environment must survive SSH disconnections.

## Monitoring

A status refresh uses one SSH command and one shared one-second sample window rather than a sequence of independent commands:

```
/proc/stat      ─┐
/proc/net/dev    │ sample 0
/proc/meminfo    │
df -Pk           │
uname / uptime   │
loadavg          │
os-release       │
sleep 1          │
/proc/stat       │ sample 1
/proc/net/dev   ─┘
```

The result is parsed locally into the server status model.

## Credentials and host identity

New SSH credentials are stored directly in Apple's Security Keychain.

Older Server Dash installations that contain the legacy encrypted `.ptk` credential files are migrated to the system Keychain on first read.

SSH host fingerprints use trust-on-first-use pinning. A host presenting a different fingerprint on a later connection is rejected before authentication.

## Project structure

```
ServerDash/
  Views/
    AddServer/        server registration
    ServerBlock/      dashboard cards
    ServerDetailView/ detailed status and history
    Terminal/         session list and Ghostty UI
    SettingView/      application settings
  Utils/              app/session coordination

Foundation/
  PTFoundation/
    PTAccountManager/ credentials and accounts
    PTServerManager/  server registry, monitoring, history, SSH client
  NMSSH/              SSH transport
  SQL/                SQLite.swift
```

The old Scripts / CodeClip / Checkpoint / JavaScript execution subsystem was intentionally removed. Common remote work should happen through the terminal; small terminal-oriented conveniences can be added without growing another execution platform.

## Build

Server Dash targets iOS 15+.

```sh
xcodebuild \
  -project ServerDash.xcodeproj \
  -scheme ServerDash \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The same simulator build runs in GitHub Actions for pull requests.

NMSSH connection-maintenance integration tests use local SSH fixtures on macOS:

```sh
python3 -m venv /tmp/server-dash-ssh-tests
/tmp/server-dash-ssh-tests/bin/pip install 'paramiko>=3,<5'
/tmp/server-dash-ssh-tests/bin/python Foundation/NMSSH/Tests/Integration/run.py
```

They cover keepalive delivery, responsive and unresponsive probes, channel allocation refusal, abrupt and protocol-level disconnects, and fresh checks after an earlier successful probe. Background suspension timing still needs testing on a physical iPhone/iPad.
