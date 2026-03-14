#!/nix/store/fwr62xmh06l8y8zfgc5m18pfap9b8az0-bash-5.3p3/bin/bash
#!/usr/bin/env bash

# Check if gnome-control-center is already running
# Note: -f matches full command line (process names are truncated to 15 chars)
# The [g] bracket trick prevents pgrep from matching itself
if /nix/store/a7mh633n3p4ly5l9v3grrg448isf3bsb-procps-4.0.4/bin/pgrep -f '[g]nome-control-center' >/dev/null 2>&1; then
  # Detect window manager and move the existing window to current workspace
  if [ -n "$SWAYSOCK" ] || /nix/store/a7mh633n3p4ly5l9v3grrg448isf3bsb-procps-4.0.4/bin/pgrep -x sway >/dev/null 2>&1; then
    # Sway
    /nix/store/wjpax7cf59yhpqvla5yr1xw96772ll10-sway-1.11/bin/swaymsg '[class="gnome-control-center"] move to workspace current, focus' 2>/dev/null || \
    /nix/store/wjpax7cf59yhpqvla5yr1xw96772ll10-sway-1.11/bin/swaymsg '[app_id="gnome-control-center"] move to workspace current, focus' 2>/dev/null || \
    /nix/store/wjpax7cf59yhpqvla5yr1xw96772ll10-sway-1.11/bin/swaymsg '[title="Settings"] move to workspace current, focus' 2>/dev/null
  elif /nix/store/a7mh633n3p4ly5l9v3grrg448isf3bsb-procps-4.0.4/bin/pgrep -x i3 >/dev/null 2>&1; then
    # i3
    /nix/store/air0mja0a5kzr4kv21w60gkl3is68052-i3-4.24/bin/i3-msg '[class="gnome-control-center"] move to workspace current, focus' 2>/dev/null
  fi
  exit 0
fi

export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_DESKTOP=gnome
export XDG_SESSION_TYPE=wayland

# Keep DBus/systemd user activation in sync with the launch environment
/nix/store/1vs3gbz4w3wrqs76z8iay5cidwrv2hy6-systemd-258.3/bin/systemctl --user import-environment XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
/nix/store/mkrhzl73l8bdjzkrmj4wi8wzw584mn52-dbus-1.14.10/bin/dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true

# Ensure SessionManager and GNOME settings-daemon plugins are available first.
/nix/store/1vs3gbz4w3wrqs76z8iay5cidwrv2hy6-systemd-258.3/bin/systemctl --user start gnome-session-manager-bridge.service 2>/dev/null || true
/nix/store/48nhpn1dv5pn74018agdz7qrbiik2sd5-coreutils-9.8/bin/timeout 5 /nix/store/cclxs655gaq8jw8bzbbsn67pvhwzwrdb-glib-2.86.3-bin/bin/gdbus wait --session org.gnome.SessionManager >/dev/null 2>&1 || true

# If gsd-rfkill started before SessionManager, it can stay half-initialized.
# Kill stale instances so DBus activation starts a fresh one in the correct env.
/nix/store/a7mh633n3p4ly5l9v3grrg448isf3bsb-procps-4.0.4/bin/pkill -f gsd-rfkill >/dev/null 2>&1 || true

# Trigger gnome-settings-daemon plugin activation (rfkill/xsettings/sound/color/screensaver-proxy).
/nix/store/1vs3gbz4w3wrqs76z8iay5cidwrv2hy6-systemd-258.3/bin/systemctl --user start gnome-settings-daemon-init.service 2>/dev/null || true

# Force DBus activation of rfkill and wait until it owns its bus name.
/nix/store/cclxs655gaq8jw8bzbbsn67pvhwzwrdb-glib-2.86.3-bin/bin/gdbus call --session --dest org.gnome.SettingsDaemon.Rfkill --object-path /org/gnome/SettingsDaemon/Rfkill --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 || true

# Wait briefly for DBus services that the Wi-Fi panel needs.
/nix/store/48nhpn1dv5pn74018agdz7qrbiik2sd5-coreutils-9.8/bin/timeout 5 /nix/store/cclxs655gaq8jw8bzbbsn67pvhwzwrdb-glib-2.86.3-bin/bin/gdbus wait --session org.gnome.SettingsDaemon.Rfkill >/dev/null 2>&1 || true

# Launch Control Center with GNOME desktop identity for its startup check.
# Keep this scoped to the process to avoid changing global session identity.
# Use our locally built version and point to the custom schemas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_DATA_DIRS="$SCRIPT_DIR/install/share:/tmp/gsds/share:$XDG_DATA_DIRS"
exec env XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome "$SCRIPT_DIR/install/bin/gnome-control-center" "$@"

