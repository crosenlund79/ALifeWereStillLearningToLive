TinserBox 2.0
=============

WHERE YOUR FILES LIVE
---------------------
Portable version (TinserBox_Portable_Win64.zip): next to TinserBox.exe
Installed version (TinserBox_Setup_Win64.exe):   Documents\TinserBox

  music\          your songs (MP3, OGG, WAV 8/16-bit)
  backgrounds\    background images (PNG, JPG)
  screenshots\    saved screenshots (folder can be changed in Settings)
  settings.cfg    settings, playlist state and per-song looks (plain text)
  presets.json    your own and edited visualizer presets (plain text, schema 1)

The installed version copies the bundled songs into Documents\TinserBox on
first launch. Updating or uninstalling never touches that folder.
Add songs by copying them into music\, by "+ Folder" / "+ Files" in the
Playlist tab, or by dragging files and folders onto the window.
"Remove from playlist" never deletes files.

PER-SONG SETTINGS (settings.cfg)
--------------------------------
Each song has a section named after its filename, for example:
  [My Song.mp3]
  background="forest.jpg"        image in backgrounds\
  color=Color(1, 0.8, 0.4, 1)     main colour
  color2=Color(0.5, 0.4, 1, 1)    second colour
  preset_mode="song"             global | song | auto
  preset="Clockwork Heart"
  sensitivity=1.2   intensity=1.1   glow=0.9   bg_motion=0.5   particle_density=1.3
Everything is optional; missing songs or images are ignored.

VISUALIZERS AND PRESETS
-----------------------
Visualizers: Waveform, Square Grid, Seven Waves, Retro Spectrum, Glowing Orbs,
The Aurora, Particle Universe, Resonance Engine, The Seven Spirits.
Built-in presets: Midnight Aurora, Stellar Drift, Clockwork Heart, Seven Souls,
Neon Pulse, Almost Nothing, Golden Thread (the original look).
Combine a main and a second visualizer, an atmosphere and the beat light in
the Visualizer tab, then Save / Save as. "Restore built-ins" brings back the
originals.

KEYBOARD (when TinserBox is focused)
------------------------------------
  Space        Play / Pause           Enter       Restart song after 2 s
  Left/Right   Seek -5 / +5 s         Up/Down     Volume
  M            Mute / Unmute          N / P       Next / Previous track
  S            Shuffle                R           Repeat: Off / All / One
  F            Fullscreen             Esc         Show / hide the interface
  H            Hide everything until H is pressed again (remembered)
  1-9          Choose preset          [ / ]       Previous / next preset
  F12          Screenshot (key configurable: screenshot_key in settings.cfg)
  F3           Diagnostics            Ctrl+Q      Quit

MEDIA KEYS
----------
Play/Pause, Next, Previous and Stop media keys go through the Windows media
controls (TinserBoxMedia.exe, next to TinserBox.exe), so they can work while
TinserBox is minimized or in the background, without taking them from other
players. If that helper is unavailable, media keys work while TinserBox is
focused.
