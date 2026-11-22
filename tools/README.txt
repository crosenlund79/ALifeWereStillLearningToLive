TinserBox 2.0
=============

WHERE YOUR FILES LIVE
---------------------
Portable version (TinserBox_Portable_Win64.zip): next to TinserBox.exe
Installed version (TinserBox_Setup_Win64.exe):   Documents\TinserBox

  music\          your songs (MP3, OGG, WAV 8/16-bit)
  backgrounds\    background images (PNG, JPG)
  screenshots\    saved screenshots (folder can be changed in Settings)
  dancers\        your own dancing companions (PNG frames; see README.txt inside)
  recordings\     recorded system audio (folder can be changed in Settings)
  moods.json      your moods: songs, order and look (plain text, schema 1)
  settings.cfg    settings and older per-song looks (plain text)
  presets.json    your own and edited visualizer presets (plain text, schema 1)

The installed version copies the bundled songs into Documents\TinserBox on
first launch. Updating or uninstalling never touches that folder.
Add songs by copying them into music\, by "+ Folder" / "+ Files" in the
Moods tab, or by dragging files and folders onto the window.
"Remove" never deletes files.

MOODS
-----
Moods replace playlists. All Music is the permanent library; a mood is a set of
songs plus a look: visualizer presets, colours, backgrounds, sensitivity,
intensity, background motion and an optional dancing companion.
  Moods tab   Click a mood to browse it (the playing song keeps playing).
              Double-click it, or "Play this mood", to start it.
              New / Rename / Delete (deleting never removes songs).
              Drag songs (Ctrl/Shift-click for several) onto a mood to add
              them; drag within a mood to reorder; drag moods to reorder them.
              Right-click songs > Moods: tick or untick moods (a song can be
              in several). Shuffle, Repeat and Next/Previous stay in the mood.
  Mood Look   Presets of the mood. Auto variation (default) picks a different
              preset for each song, never mid-song; Fixed always uses one.
              Backgrounds rotate per song. Colours apply to every preset (or
              let each preset use its own). Dancer: None keeps it off.
              "Save current look to this mood" stores what you see as a new
              preset of the mood. Changing the Visualizer tab is a temporary
              override until you save it to the mood.
Your old playlists became moods automatically (names, songs and order kept);
playlists.json is left untouched. Missing songs stay listed and are skipped.

OLDER PER-SONG SETTINGS (settings.cfg)
--------------------------------------
Songs played from All Music still use these. Each song has a section named after its filename, for example:
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
Visualizers: Multi-Waveform (1-7 lines), Square Grid, Retro Spectrum, The Aurora,
Particle Universe, Resonance Engine, The Seven Spirits, Harmonic Ribbons,
Pulse Rings, Northern Lights. Each has its own settings in the Visualizer tab, and
every visualizer takes its colours from the preset's main/second colours and seven
element colours (Reset colours restores them; "Use for this mood" keeps them for
the mood selected in the Moods tab).
Built-in presets: Midnight Aurora, Stellar Drift, Clockwork Heart, Seven Souls,
Neon Pulse, Almost Nothing, Silk Harmonics, Echo Chamber, Polar Night,
Golden Thread (the original look).
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
  Ctrl+R       Start / stop recording system audio
  Ctrl+M       Mini player: small, borderless, always on top (drag it anywhere;
               Ctrl+M again restores the window). Always off at launch.

VISUALIZE SPOTIFY AND OTHER APPS (Windows)
------------------------------------------
Settings > Audio source > System audio: TinserBox stops its own player and
visualizes whatever Windows is playing (Spotify, a browser, games), using
loopback capture of your default output device: no drivers or admin rights.
Control playback in that app (media keys go to it). The current song's title
and artist come from Windows' media controls, so the song pop-up, per-song
looks (section "Artist - Title" in settings.cfg) and automatic atmosphere
work for those songs too. Visuals lag the sound by roughly 0.1 s. Click a
song in the Moods tab (or choose TinserBox player) to return.

DANCING COMPANIONS
------------------
A mood chooses its dancer and personality in Mood Look (None = off). For All Music,
Visualizer tab > Dancing companion: switch a dancer on, pick a character and
personality, and set how strongly the visualizer's light colours it (0-100%).
Built in: Aria, an illustrated dancer with short choreographed moves that follow
the tempo and energy (gentle in quiet passages). Personalities: shy, playful,
energetic, elegant, clumsy. Add your own in dancers\ (next to music\): one folder per
dancer with transparent PNG frames, or a single PNG; see dancers\README.txt.

RECORDING (Windows)
-------------------
Settings > Recording, or Ctrl+R: records everything Windows plays (TinserBox
included, once) from your default output device. Saved as MP3 (320 kbps) using
Windows' built-in encoder; if that encoder is unavailable the recording is saved
as WAV instead, and TinserBox tells you which. Default name: date and time; type a
name before starting, or use "Rename last" afterwards. Recordings go to
recordings\ (changeable). Recording only starts when you press the button, and
TinserBox can play the recordings back (add the folder in the Moods tab).

MEDIA KEYS
----------
Play/Pause, Next, Previous and Stop media keys go through the Windows media
controls (TinserBoxMedia.exe, next to TinserBox.exe), so they can work while
TinserBox is minimized or in the background, without taking them from other
players. If that helper is unavailable, media keys work while TinserBox is
focused.
