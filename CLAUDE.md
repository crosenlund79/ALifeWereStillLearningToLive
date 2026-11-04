# TinserBox — notes for Claude

## Installer reporting (applies to every build)
The Windows build is `tools/build_windows.sh` (see README.md). After every build attempt, end
the response with:

- **Latest installer:** exact absolute path to `dist/TinserBox_Setup_Win64.exe`
  (the script prints it as its last line on success).
- **Download:** attach that file to the reply (SendUserFile) so there is a direct link.
- **Build status:** Success or Failure.

Only report the installer produced by the build just run. The script deletes old artifacts
first, so if it fails, say clearly that no installer was generated, and give no path or link.
