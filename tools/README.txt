TinserBox
=========

WHERE YOUR FILES LIVE
---------------------
Portable version (TinserBox_Portable_Win64.zip):
  Everything sits next to TinserBox.exe:
    music\          your songs (MP3, OGG, WAV 8/16-bit)
    backgrounds\    background images (PNG, JPG)
    settings.cfg    created on first launch

Installed version (TinserBox_Setup_Win64.exe):
  Your library is in Documents\TinserBox:
    Documents\TinserBox\music\
    Documents\TinserBox\backgrounds\
    Documents\TinserBox\settings.cfg
  The bundled songs are copied there on first launch. Updating or
  uninstalling TinserBox never removes this folder.

Add or remove songs and backgrounds by copying files into these folders,
then restart TinserBox. Missing folders are created automatically.

settings.cfg is a plain text file. Each song has a section named after its
filename, e.g.
  [My Song.mp3]
  background="forest.jpg"
  color=Color(1, 0.8, 0.4, 1)
App-wide settings (EQ, sensitivity, volume, shuffle, repeat) are under [_app].

KEYBOARD SHORTCUTS (when TinserBox is focused)
----------------------------------------------
  Space        Play / Pause
  Enter        Restart song after 2 seconds
  Left/Right   Seek -5 / +5 seconds
  Up/Down      Volume
  M            Mute / Unmute
  N / P        Next / Previous track
  S            Shuffle on/off
  R            Repeat: Off / All / One
  F            Fullscreen
  Esc          Show / hide the interface
  Ctrl+Q       Quit (also the Quit button)

The speaker icon mutes/unmutes. "Hide window frame" (Visualizer tab) hides the
Windows title bar and borders while the interface is hidden; move the mouse or
press a key to bring both back.

MEDIA KEYS
----------
Play/Pause, Next, Previous and Stop media keys work through the Windows media
controls (the same system used by Spotify, browsers, etc.), so they also work
while TinserBox is minimized or in the background. Windows sends media keys to
whichever media app most recently played, so TinserBox does not take them away
from other players. This relies on TinserBoxMedia.exe staying next to
TinserBox.exe; if it is missing, media keys only work while TinserBox is focused.
