TIM I3 SETTINGS ( fork of gnome settings )
====================

This is a fork that performs small modification to get the control center to work under i3.
Notably:

- remove gnome / unity usage restriction
- add i3 integration / startup script behavior for existing-window focus and faster startup waits
- add Nix flake packaging for `control-center` command
- ship prebuilt binaries in `prebuilt/` for flake packaging (x86_64-linux)
- remove the `Multitasking`, `Wellbeing`, `Accessibility`, and `Online Accounts` sections from the panel list

Repository history note:

- `main` was intentionally squashed to a single commit to reduce clone/download time for future checkouts.
- the previous full commit history is preserved on `old-commit-history`.
