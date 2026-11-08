# TinserBox — notes for Claude

## Mandatory build & delivery (every code change or development iteration)
This is a permanent project requirement; apply it automatically, without being reminded.

1. Build the latest Windows x64 executable and installer with `tools/build_windows.sh`
   (see README.md), producing `dist/TinserBox_Setup_Win64.exe` with the newest changes.
2. Commit and push the source. Every push (except docs-only changes) runs
   `.github/workflows/release.yml`, which builds on GitHub and publishes
   `TinserBox_Setup_Win64.exe` and `TinserBox_Portable_Win64.zip` as a new GitHub Release.
   Wait for that run to finish and download both release assets to verify the links work.
3. Attach the local installer to the reply (SendUserFile) whenever possible.
4. End the response with:
   - **Latest installer:** exact absolute path to `dist/TinserBox_Setup_Win64.exe` and its build
     date/time (the build script prints both as its last line on success).
   - **Download:** the verified GitHub Release link
     `https://github.com/crosenlund79/ALifeWereStillLearningToLive/releases/download/<tag>/TinserBox_Setup_Win64.exe`
     (plus the portable ZIP link), and the attached file.
   - **Build status:** Success or Failure (local build and GitHub Release separately if they differ).

Never present an older installer as the latest. The build script deletes old artifacts first;
if the build or publishing fails, say so clearly and give no path or link for that build.
