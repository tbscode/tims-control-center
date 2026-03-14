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
    
    # We need newer blueprint-compiler than what's in nixpkgs for GNOME 48/51
    my-blueprint = pkgs.blueprint-compiler.overrideAttrs (old: {
      src = pkgs.fetchgit {
        url = "https://gitlab.gnome.org/GNOME/blueprint-compiler.git";
        rev = "c59e5bc4f7c6b76bb578eeb6d42c5d5416c1a078";
        hash = "sha256-QkBSxgN7kydMxVouI0baBngkceYLfQFlrrOEp35BX1Q=";
      };
    });

    my-libgxdp = pkgs.stdenv.mkDerivation {
      pname = "libgxdp";
      version = "0.0.0-unstable-2025-11-25";
      src = pkgs.fetchgit {
        url = "https://gitlab.gnome.org/GNOME/libgxdp.git";
        rev = "d45e1c572752604a7a8dd8651657342bb6ac0961";
        hash = "sha256-Zb0FdcSye4H3XWIfut878YiSiUr8MioNbTE9SymtAjw=";
      };
      nativeBuildInputs = [ pkgs.meson pkgs.ninja pkgs.pkg-config pkgs.wayland-scanner ];
      buildInputs = [ pkgs.glib pkgs.gtk4 pkgs.wayland pkgs.dbus ];
      mesonFlags = [ "-Dtests=false" ]; # Skip tests that require dbus-run-session
      
      # We just need the built library, but it doesn't install anything by default when run stand-alone.
      # Actually, libgxdp in this tree is meant to be built as a subproject statically.
      # Meson will link it directly into gnome-control-center if we use it as a subproject.
    };

    my-gcc = (pkgs.gnome-control-center.override {
      gsettings-desktop-schemas = my-schemas;
    }).overrideAttrs (old: {
      src = ./.;
      patches = [];
      doCheck = false;
      
      # Use the specific version of blueprint-compiler via nativeBuildInputs
      # and remove wrap downloads which cannot work inside the Nix build sandbox
      mesonFlags = (old.mesonFlags or []) ++ [
        "-Dwrap_mode=nodownload"
      ];

      # Remove blueprint.wrap since we provide it via nix
      # Also remove other wrap files to force using the system's libraries provided by Nixpkgs
      preConfigure = (old.preConfigure or "") + ''
        rm -f subprojects/*.wrap
      '';

      # Inject our updated subprojects
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ my-blueprint pkgs.git ];
      buildInputs = (old.buildInputs or []);

      postInstall = (old.postInstall or "") + ''
        # We need to make sure the app finds the schemas at runtime.
        # Instead of wrapping the executable recursively, we will just provide the control-center script.
        mkdir -p $out/bin
        
        # We inject paths for the custom schemas into XDG_DATA_DIRS
        cat > $out/bin/control-center << 'EOF'
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

        # Add the schemas that were required during the build to the data dirs
        export XDG_DATA_DIRS="$out/share:${my-schemas}/share:$XDG_DATA_DIRS"

        # Launch the actual binary
        exec env XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome "$out/bin/gnome-control-center" "$@"
        EOF

        chmod +x $out/bin/control-center
      '';
    });
  in {
    packages.x86_64-linux.default = my-gcc;
  };
}
