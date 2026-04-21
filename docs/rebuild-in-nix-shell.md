# Rebuild `prebuilt/` in a Nix shell

This project can be rebuilt fully (real binaries/resources/translations) from source in a dev shell, then copied into `prebuilt/`.

## Quick way

From `modules/tims-control-center`:

```bash
./rebuild-prebuilt.sh
```

The script does:

1. `nix develop nixpkgs#gnome-control-center`
2. `meson setup/compile/install` to `/tmp/tims-cc-install`
3. replaces `prebuilt/{bin,lib,libexec,share}` from that install
4. runs `nix build .`
5. removes local build artifacts (`_build_local`, local `result`)

## Manual commands

```bash
nix develop nixpkgs#gnome-control-center -c bash -lc '
  rm -rf _build_local /tmp/tims-cc-install
  meson setup _build_local --prefix=/tmp/tims-cc-install
  meson compile -C _build_local
  meson install -C _build_local
'

rm -rf prebuilt/bin prebuilt/lib prebuilt/libexec prebuilt/share
cp -a /tmp/tims-cc-install/{bin,lib,libexec,share} prebuilt/

nix build .
```

## Notes

- The Meson changes in `panels/background/meson.build`, `panels/system/meson.build`, and `subprojects/gsettings-desktop-schemas/meson.build` are needed so fallback `gsettings-desktop-schemas` works cleanly in this environment.
- UI string verification can be done with:

```bash
rg -a "Tim's Controls" prebuilt/bin/gnome-control-center prebuilt/share/applications/org.gnome.Settings.desktop
```
