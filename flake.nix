{
  description = "Custom GNOME Control Center";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };

    # Package prebuilt binaries and patch ELF dependencies.
    my-gcc = pkgs.stdenv.mkDerivation {
      pname = "gnome-control-center-prebuilt";
      version = "49.5-custom";

      src = ./prebuilt;

      nativeBuildInputs = [ pkgs.autoPatchelfHook ];

      buildInputs = [
        pkgs.glib
        pkgs.gtk4
        pkgs.libadwaita
        pkgs.gnome-settings-daemon
        pkgs.gnome-desktop
        pkgs.gnome-online-accounts
        pkgs.libgtop
        pkgs.libsecret
        pkgs.polkit
        pkgs.libpwquality
        pkgs.gcr
        pkgs.upower
        pkgs.pulseaudio
        pkgs.colord
        pkgs.accountsservice
        pkgs.udisks2
        pkgs.cups
        pkgs.libnma-gtk4
        pkgs.modemmanager
        pkgs.networkmanager
        pkgs.gnome-bluetooth
        pkgs.libwacom
        pkgs.cairo
        pkgs.pango
        pkgs.harfbuzz
        pkgs.json-glib
        pkgs.libsoup_3
        pkgs.libepoxy
        pkgs.libgudev
        pkgs.tecla
        pkgs.krb5
        pkgs.samba
        pkgs.ibus
        pkgs.colord-gtk4
        pkgs.gst_all_1.gstreamer
        pkgs.gst_all_1.gst-plugins-base
        pkgs.gst_all_1.gst-plugins-good
      ];

      installPhase = ''
        mkdir -p $out
        cp -r . $out/
        
        # Backup the original binary
        mv $out/bin/gnome-control-center $out/bin/.gnome-control-center-wrapped

        # Create a wrapper script that simulates control_center.sh
        cat > $out/bin/control-center << 'EOF'
        #!/usr/bin/env bash

        SCRIPT_PATH="$(readlink -f "''${BASH_SOURCE[0]}")"
        SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

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

        # Ensure bundled and system schemas/resources are available to GSettings and GTK.
        data_dirs=()
        schema_dirs=()

        add_schema_dir() {
          local d="$1"
          if [ -d "$d" ]; then
            schema_dirs+=("$d")
          fi
        }

        for base in /run/current-system/sw /etc/profiles/per-user/$USER /nix/var/nix/profiles/default; do
          if [ -d "$base/share" ]; then
            data_dirs+=("$base/share")
          fi
          add_schema_dir "$base/share/glib-2.0/schemas"
          for schema_root in "$base"/share/gsettings-schemas/*; do
            if [ -d "$schema_root/glib-2.0/schemas" ]; then
              data_dirs+=("$schema_root")
              add_schema_dir "$schema_root/glib-2.0/schemas"
            fi
          done
        done

        data_dirs+=("$SCRIPT_DIR/../share")
        add_schema_dir "$SCRIPT_DIR/../share/glib-2.0/schemas"

        joined_data_dirs=""
        for d in "''${data_dirs[@]}"; do
          if [ -z "$joined_data_dirs" ]; then
            joined_data_dirs="$d"
          else
            joined_data_dirs="$joined_data_dirs:$d"
          fi
        done
        export XDG_DATA_DIRS="$joined_data_dirs"

        schema_merge_dir="/tmp/tims-control-center-schema-merge-$UID"
        rm -rf "$schema_merge_dir"
        mkdir -p "$schema_merge_dir"
        for d in "''${schema_dirs[@]}"; do
          cp -f "$d"/*.xml "$schema_merge_dir" 2>/dev/null || true
          cp -f "$d"/*.gschema.override "$schema_merge_dir" 2>/dev/null || true
        done

        # Compatibility patch for custom control-center builds expecting this key.
        if [ -f "$schema_merge_dir/org.gnome.desktop.session.gschema.xml" ] && ! ${pkgs.gnugrep}/bin/grep -q 'name="save-restore"' "$schema_merge_dir/org.gnome.desktop.session.gschema.xml"; then
          ${pkgs.gnused}/bin/sed -i '/<\/schema>/i\  <key name="save-restore" type="b">\n    <default>true<\/default>\n    <summary>Restore session</summary>\n    <description>Whether to restore previous session state.<\/description>\n  <\/key>' "$schema_merge_dir/org.gnome.desktop.session.gschema.xml"
        fi

        ${pkgs.glib.dev}/bin/glib-compile-schemas "$schema_merge_dir" >/dev/null
        export GSETTINGS_SCHEMA_DIR="$schema_merge_dir"
        export GST_PLUGIN_SYSTEM_PATH="${pkgs.gst_all_1.gst-plugins-base}/lib/gstreamer-1.0:${pkgs.gst_all_1.gst-plugins-good}/lib/gstreamer-1.0"

        exec env XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome "$SCRIPT_DIR/.gnome-control-center-wrapped" "$@"
        EOF

        chmod +x $out/bin/control-center
      '';

      meta.mainProgram = "control-center";
    };
  in {
    packages.x86_64-linux.default = my-gcc;
    apps.x86_64-linux.default = {
      type = "app";
      program = "${my-gcc}/bin/control-center";
    };
  };
}
