# Live View

A full-window viewer for the Canon R6 on a laptop. It shows exactly what the
camera's own screen shows, with menus, settings and overlays, and the camera's
screen keeps working at the same time.

## Setup: HDMI capture (the way to get menus and both screens)

The camera's menus and shooting info only leave the camera over **HDMI**. Over
USB it only sends the bare picture, and Canon turns the rear screen off while
a computer is pulling live view. So this route needs two small parts:

- a **USB HDMI capture stick** (about $15-20; any "USB 3.0 HDMI video capture"
  that does 1080p60 works on macOS and Windows without drivers)
- a **micro-HDMI (Type D) to HDMI cable**. The R6's HDMI port is the micro one
  under the side door.

Camera side (R6):

1. Plug the cable into the camera and the capture stick, the stick into the laptop.
2. Set **HDMI display** to **Camera + External monitor** so both screens stay on.
   (It's in the red shooting menu; if it's set to External monitor only, the
   rear screen goes dark.)
3. If the laptop shows "no signal", set **HDMI resolution** to **1080p** in the
   setup (yellow) menu. Some sticks don't take the R6's 4K output.
4. **INFO** cycles what's overlaid. Keep the info display on to see settings,
   or cycle to the clean view when you want just the picture.
5. Set **Auto power off** to **Disable** so the feed doesn't drop.

Laptop side:

```sh
python3 tools/liveview/bridge.py
```

It opens http://localhost:8765. Pick the capture stick under **Source** (it is
picked automatically if its name contains "capture", "HDMI" or "USB Video").
Opening `viewer.html` directly in Chrome works too.

## Viewer tools

Everything is off by default except the histogram, since the camera draws its
own overlays. Turn on what helps:

| Key | Does |
| --- | --- |
| P | Focus peaking (slider = sensitivity) |
| Z | Zebras on highlights (90 / 95 / 100%) |
| H | Histogram (white bar on the right edge = highlights clipping) |
| G | Cycle grid |
| M | Mirror |
| R | Rotate 180° (camera mounted upside down) |
| S | Save the current frame as PNG |
| C | Clean view, hide all controls (Esc brings them back) |
| F | Fullscreen |

Settings are remembered. Controls fade out when the mouse is still.

## USB: live view plus camera control (the Mac app)

No extra hardware. One-time setup in Terminal:

```sh
mkdir -p ~/liveview && cd ~/liveview
curl --remote-name-all https://raw.githubusercontent.com/brettmboggs/brettboggs.dev/claude/nice-archimedes-esk7jj/tools/liveview/{viewer.html,bridge.py,icon.png}
python3 -m pip install --user gphoto2      # add --break-system-packages if pip refuses
python3 bridge.py --install
```

That builds **Live View.app** in `~/Applications` and shows it in Finder. Drag it
into the Dock. From then on: plug in the camera, click the icon. Closing the
window (or **Quit**) hands the camera back. Re-run the last line after
downloading a newer version. Log: `~/Library/Logs/Live View.log`.

Before clicking: quit EOS Utility, turn the camera's Wi-Fi off.

### Shooting

- **Shoot** (Space). Shots save to the card; tick *Copy shots to laptop* to also
  get them in `~/Pictures/Live View`.
- **Modes:** Self-timer (2/5/10 s, with beeps) · Bracket for HDR (3 or 5 shots,
  ⅔/1/2 EV apart, then puts your exposure back) · Focus stack (N shots, moving
  focus a set step each time) · Time-lapse (every N seconds). Space or Esc stops.
- Shutter speed, aperture, ISO, exposure compensation, white balance, focus
  nudges (`[` `]`, bigger `{` `}`) and Autofocus (A).

### Assist (I)

- **Exposure:** reads the live picture and says *Looks good*, *Highlights
  clipping*, or *try −⅔ EV*. **Fix** applies it (exposure compensation, or
  shutter speed in M). Needs the camera's exposure simulation on (the default).
- **Focus meter:** sharpness inside the focus box; full and green is sharpest.
  Click the picture to move the box.
- **Precision focus** (D, or double-click the picture): sweeps the focus motor,
  finds the sharpest point for the box, and parks there. Lens on AF.
- **Ghost of last shot:** overlays the previous frame faintly, for lining up a
  series or matching a composition.

Extras: `python3 bridge.py --host 0.0.0.0` lets an iPad on the same Wi-Fi open
the viewer at `http://<laptop-ip>:8765`, and `/stream.mjpg` is a plain MJPEG
feed for OBS or VLC.
