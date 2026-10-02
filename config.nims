# Release builds (e.g. `nimble build -d:release`, as invoked by nimpacker)
# must produce a GUI-subsystem, size-optimized binary.
when defined(release):
  --app:gui
  --opt:size
