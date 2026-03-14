{
  description = "Custom GNOME Control Center";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    
    my-schemas = pkgs.gsettings-desktop-schemas.overrideAttrs (old: {
      src = pkgs.fetchgit {
        url = "https://gitlab.gnome.org/GNOME/gsettings-desktop-schemas.git";
        rev = "79bc4ac873aee516b668bc2fb6e8aadf5eba4bb2";
        hash = "sha256-gACQK2eRiayerJQgNZ2uAivAGs/ySwqlBi2pfkIp0x4=";
      };
      patches = []; # remove any old patches
    });
    
    # Create an extremely minimal wrapper that just executes the existing build
    # we did in the folder. The easiest path is often just wrapping what works!
    my-gcc = pkgs.writeShellScriptBin "control-center" ''
        #!/usr/bin/env bash

        # Check if gnome-control-center is already running
        if ${pkgs.procps}/bin/pgrep -f '[g]nome-control-center' >/dev/null 2>&1; then
          if [ -n "$SWAYSOCK" ] || ${pkgs.procps}/bin/pgrep -x sway >/dev/null 2>&1; then
            ${pkgs.sway}/bin/swaymsg '[class="gnome-control-center"] move to workspace current, focus' 2>/dev/null || \
            ${pkgs.sway}/bin/swaymsg '[app_id="gnome-control-center"] move to workspace current, focus' 2>/dev/null || \
            ${pkgs.sway}/bin/swaymsg '[title="Settings"] move to workspace current, focus' 2>/dev/null
          elif ${pkgs.procps}/bin/pgrep -x i3 >/dev/null 2>&1; then
            ${pkgs.i3}/bin/i3-msg '[class="gnome-control-center"] move to workspace current, focus' 2>/dev/null
          fi
          exit 0
        fi

        export XDG_CURRENT_DESKTOP=GNOME
        export XDG_SESSION_DESKTOP=gnome
        export XDG_SESSION_TYPE=wayland

        # Keep DBus/systemd user activation in sync with the launch environment
        ${pkgs.systemd}/bin/systemctl --user import-environment XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
        ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true

        # Ensure SessionManager and GNOME settings-daemon plugins are available first.
        ${pkgs.systemd}/bin/systemctl --user start gnome-session-manager-bridge.service 2>/dev/null || true
        ${pkgs.coreutils}/bin/timeout 0.5 ${pkgs.glib.bin}/bin/gdbus wait --session org.gnome.SessionManager >/dev/null 2>&1 || true

        # If gsd-rfkill started before SessionManager, it can stay half-initialized.
        ${pkgs.procps}/bin/pkill -f gsd-rfkill >/dev/null 2>&1 || true

        # Trigger gnome-settings-daemon plugin activation
        ${pkgs.systemd}/bin/systemctl --user start gnome-settings-daemon-init.service 2>/dev/null || true

        # Force DBus activation of rfkill and wait
        ${pkgs.glib.bin}/bin/gdbus call --session --dest org.gnome.SettingsDaemon.Rfkill --object-path /org/gnome/SettingsDaemon/Rfkill --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 || true
        ${pkgs.coreutils}/bin/timeout 0.5 ${pkgs.glib.bin}/bin/gdbus wait --session org.gnome.SettingsDaemon.Rfkill >/dev/null 2>&1 || true

        # Define where the actual built version lives (we assume it's in the repo directory)
        REPO_DIR="/home/tim/development/tims-control-center"
        
        # Inject the custom schemas 
        export XDG_DATA_DIRS="$REPO_DIR/install/share:${my-schemas}/share:$XDG_DATA_DIRS"

        # Launch the actual binary built locally
        exec env XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome "$REPO_DIR/install/bin/gnome-control-center" "$@"
    '';
  in {
    packages.x86_64-linux.default = my-gcc;
  };
}
