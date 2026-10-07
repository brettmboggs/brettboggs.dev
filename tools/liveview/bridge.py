#!/usr/bin/env python3
"""Live view and remote control for a Canon EOS over USB.

    python3 -m pip install --user gphoto2   # once
    python3 bridge.py             # run from Terminal
    python3 bridge.py --install   # or: build "Live View.app" in ~/Applications

Opens the viewer at http://localhost:8765. Ctrl+C (or Quit in the viewer, or
closing the app window) hands the camera back.

With the gphoto2 Python package installed you get live view plus control
(focus, shutter, ISO, aperture, shutter speed...). Without it, the bridge falls
back to the gphoto2 command line tool for live view only.

Endpoints: /            the viewer
           /next.jpg    the next live view frame (waits for it)
           /stream.mjpg plain MJPEG, for OBS, VLC, etc.
           /status      JSON health
           /settings    JSON camera settings
           /cmd         POST {"cmd": "shoot" | "af" | "mf" | "set" | "download", ...}
           /ping /bye   viewer heartbeat (app mode quits when the window closes)
           /quit        POST, release the camera and exit
"""
import argparse
import http.server
import json
import os
import platform
import plistlib
import queue
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from collections import deque
import signal
import urllib.request
from urllib.parse import parse_qs, urlparse

try:
    import gphoto2 as gp
except ImportError:
    gp = None

HERE = os.path.dirname(os.path.abspath(__file__))
APP_NAME = "Live View"
DEFAULT_DOWNLOADS = os.path.expanduser("~/Pictures/Live View")
SOI, EOI = b"\xff\xd8", b"\xff\xd9"

# Settings shown in the viewer, in display order.
WATCH = ["shutterspeed", "aperture", "iso", "exposurecompensation", "whitebalance",
         "drivemode", "focusmode", "imageformat", "autoexposuremode",
         "batterylevel", "availableshots"]


class Frames:
    """Latest JPEG frame, shared between the camera thread and HTTP clients."""

    def __init__(self):
        self.cond = threading.Condition()
        self.jpeg = None
        self.seq = 0
        self.fps = 0.0
        self.state = "starting"
        self.log = deque(maxlen=12)
        self._times = deque(maxlen=30)

    def put(self, jpeg):
        now = time.monotonic()
        with self.cond:
            self.jpeg = jpeg
            self.seq += 1
            self.state = "live"
            self._times.append(now)
            if len(self._times) > 1:
                self.fps = (len(self._times) - 1) / (self._times[-1] - self._times[0] or 1)
            self.cond.notify_all()

    def next_after(self, seq, timeout):
        with self.cond:
            self.cond.wait_for(lambda: self.seq > seq, timeout)
            return self.seq, self.jpeg if self.seq > seq else None

    def note(self, state, line=None):
        with self.cond:
            self.state = state
            if line:
                self.log.append(line)
                print(f"[camera] {line}", flush=True)


def release_camera_on_macos():
    # macOS grabs every PTP camera the moment it is plugged in (PTPCamera /
    # ptpcamerad), which stops anything else from claiming the USB device.
    if platform.system() == "Darwin":
        for name in ("ptpcamerad", "PTPCamera"):
            subprocess.run(["killall", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ---- full control, via the gphoto2 Python package --------------------------------

class Job:
    def __init__(self, cmd):
        self.cmd = cmd
        self.done = threading.Event()
        self.result = {"ok": False, "error": "camera not connected"}


class Controller:
    """Owns the camera. Every USB call happens on this one thread."""

    control = True

    def __init__(self, frames, keep_screen, download_dir):
        self.frames = frames
        self.keep_screen = keep_screen
        self.download_dir = download_dir
        self.jobs = queue.Queue()
        self.settings = {}
        self.settings_lock = threading.Lock()
        self.stop = threading.Event()
        self.cam = None
        self.missing = set()
        self.af_until = 0

    # -- public, called from HTTP threads
    def submit(self, cmd, timeout=15):
        job = Job(cmd)
        self.jobs.put(job)
        if not job.done.wait(timeout):
            return {"ok": False, "error": "camera busy, timed out"}
        return job.result

    def snapshot(self):
        with self.settings_lock:
            return dict(self.settings)

    # -- camera thread
    def run(self):
        while not self.stop.is_set():
            release_camera_on_macos()
            self.frames.note("connecting", "looking for the camera")
            try:
                self.cam = gp.Camera()
                self.cam.init()
                self.frames.note("connecting", "connected: " + self._model())
                self.missing.clear()
                self._set_choice("capturetarget", "Memory card")
                self._loop()
            except gp.GPhoto2Error as exc:
                self.frames.note("disconnected", f"{exc} (retrying)")
                if exc.code == gp.GP_ERROR_MODEL_NOT_FOUND:
                    self.frames.note("disconnected", "no camera found: is it on, plugged in, and EOS Utility closed?")
            except Exception as exc:  # never let the camera thread die
                self.frames.note("disconnected", f"unexpected error: {exc!r} (retrying)")
            finally:
                self._close()
                self._fail_pending()
            self.stop.wait(2)

    def _loop(self):
        first = True
        last_read = 0
        while not self.stop.is_set():
            self._run_jobs()
            if self.af_until and time.monotonic() > self.af_until:
                self.af_until = 0
                self._try(lambda: self._set_value("autofocusdrive", 0))
            preview = self.cam.capture_preview()
            self.frames.put(bytes(memoryview(preview.get_data_and_size())))
            if first:
                first = False
                self._keep_camera_usable()
            if time.monotonic() - last_read > 1.5:
                last_read = time.monotonic()
                self._read_settings()

    def _keep_camera_usable(self):
        """Ask the camera to keep its own screen on and its buttons unlocked."""
        if not self.keep_screen:
            return
        out = self._find_widget(["output", "evfoutputdevice"], label="Camera Output")
        if out:
            choices = self._choices(out)
            both = next((c for c in choices if c.replace(" ", "") == "TFT+PC"), None)
            if both:
                ok = self._try(lambda: self._set_widget(out, both))
                self.frames.note("live", "camera screen kept on" if ok else "camera refused to keep its screen on")
        self._try(lambda: self._set_value("uilock", 0))

    def _run_jobs(self):
        while True:
            try:
                job = self.jobs.get_nowait()
            except queue.Empty:
                return
            try:
                job.result = {"ok": True, **(self._do(job.cmd) or {})}
            except gp.GPhoto2Error as exc:
                job.result = {"ok": False, "error": str(exc)}
            except (KeyError, ValueError) as exc:
                job.result = {"ok": False, "error": f"bad request: {exc}"}
            job.done.set()

    def _do(self, cmd):
        kind = cmd["cmd"]
        if kind == "set":
            name, value = cmd["name"], str(cmd["value"])
            self._set_choice(name, value, strict=True)
            self._read_settings()
            return {"settings": self.snapshot()}
        if kind == "download":
            self.download_dir = DEFAULT_DOWNLOADS if cmd.get("on") else None
            return {"download": self.download_dir}
        if kind == "af":
            self._set_value("autofocusdrive", 1)
            self.af_until = time.monotonic() + 1.2
            return None
        if kind == "mf":
            step = max(-3, min(3, int(cmd["step"])))
            if step:
                self._set_choice("manualfocusdrive", f"{'Near' if step < 0 else 'Far'} {abs(step)}", strict=True)
            return None
        if kind == "shoot":
            path = self.cam.capture(gp.GP_CAPTURE_IMAGE)
            name = os.path.join(path.folder, path.name)
            saved = None
            if self.download_dir:
                os.makedirs(self.download_dir, exist_ok=True)
                saved = os.path.join(self.download_dir, path.name)
                self.cam.file_get(path.folder, path.name, gp.GP_FILE_TYPE_NORMAL).save(saved)
            self._keep_camera_usable()
            self.frames.note("live", f"shot {name}" + (f", saved to {saved}" if saved else ""))
            return {"file": path.name, "saved": saved}
        raise ValueError(kind)

    def _read_settings(self):
        out = {}
        for name in WATCH:
            if name in self.missing:
                continue
            try:
                w = self.cam.get_single_config(name)
            except gp.GPhoto2Error:
                self.missing.add(name)
                continue
            entry = {"label": w.get_label(), "value": str(w.get_value()), "readonly": bool(w.get_readonly())}
            if w.get_type() in (gp.GP_WIDGET_RADIO, gp.GP_WIDGET_MENU):
                entry["choices"] = self._choices(w)
            out[name] = entry
        with self.settings_lock:
            self.settings = out

    # -- helpers
    def _model(self):
        try:
            return self.cam.get_summary().text.split("Model:")[1].splitlines()[0].strip()
        except Exception:
            return "camera"

    @staticmethod
    def _choices(widget):
        return [widget.get_choice(i) for i in range(widget.count_choices())]

    def _find_widget(self, names, label=None):
        for name in names:
            try:
                return self.cam.get_single_config(name)
            except gp.GPhoto2Error:
                pass
        if label:
            try:
                return self.cam.get_config().get_child_by_label(label)
            except gp.GPhoto2Error:
                pass
        return None

    def _set_widget(self, widget, value):
        widget.set_value(value)
        self.cam.set_single_config(widget.get_name(), widget)

    def _set_value(self, name, value):
        widget = self.cam.get_single_config(name)
        self._set_widget(widget, value)

    def _set_choice(self, name, value, strict=False):
        try:
            widget = self.cam.get_single_config(name)
            if value not in self._choices(widget):
                raise ValueError(f"{name} has no option {value!r}")
            self._set_widget(widget, value)
        except (gp.GPhoto2Error, ValueError):
            if strict:
                raise

    @staticmethod
    def _try(fn):
        try:
            fn()
            return True
        except gp.GPhoto2Error:
            return False

    def _fail_pending(self):
        while True:
            try:
                job = self.jobs.get_nowait()
            except queue.Empty:
                return
            job.done.set()

    def _close(self):
        if self.cam is not None:
            try:
                self.cam.exit()  # ends live view; the camera gets its screen and buttons back
            except Exception:
                pass
            self.cam = None


# ---- live view only, via the gphoto2 command line tool ----------------------------

def split_jpegs(buf, emit):
    """Pull complete JPEGs out of buf (a bytearray), leaving any partial tail."""
    while True:
        start = buf.find(SOI)
        if start < 0:
            del buf[:-1]  # keep a trailing 0xFF in case it starts the next SOI
            return
        end = buf.find(EOI, start + 2)
        if end < 0:
            del buf[:start]
            return
        emit(bytes(buf[start:end + 2]))
        del buf[:end + 2]


class CliViewer:
    control = False

    def __init__(self, frames, gphoto2):
        self.frames = frames
        self.gphoto2 = gphoto2
        self.stop = threading.Event()
        self.proc = None

    def submit(self, cmd, timeout=0):
        return {"ok": False, "error": "camera controls need the gphoto2 Python package: python3 -m pip install --user gphoto2"}

    def snapshot(self):
        return {}

    def run(self):
        while not self.stop.is_set():
            release_camera_on_macos()
            self.frames.note("connecting", "starting live view (view only)")
            try:
                self.proc = subprocess.Popen([self.gphoto2, "--stdout", "--capture-movie"],
                                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
            except OSError as exc:
                self.frames.note("error", f"could not run gphoto2: {exc}")
                self.stop.wait(3)
                continue

            def drain_stderr(proc=self.proc):
                for raw in proc.stderr:
                    line = raw.decode("utf-8", "replace").strip()
                    if line and not line.startswith("Capturing preview frames"):
                        self.frames.note(self.frames.state, line)

            threading.Thread(target=drain_stderr, daemon=True).start()
            buf = bytearray()
            fd = self.proc.stdout.fileno()
            while True:
                chunk = os.read(fd, 1 << 16)
                if not chunk:
                    break
                buf += chunk
                split_jpegs(buf, self.frames.put)
                if len(buf) > 8 << 20:
                    buf.clear()
            code = self.proc.wait()
            if not self.stop.is_set():
                self.frames.note("disconnected", f"gphoto2 exited ({code}), retrying in 2s")
            self.stop.wait(2)

    def close(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()  # SIGTERM lets gphoto2 end live view cleanly


class NoCamera:
    control = False

    def submit(self, cmd, timeout=0):
        return {"ok": False, "error": "no camera driver installed"}

    def snapshot(self):
        return {}


# ---- lifecycle -------------------------------------------------------------------------

class Lifecycle:
    """Clean shutdown, plus (in app mode) quitting once the viewer window is gone."""

    IDLE = 150     # seconds without any request from a viewer
    AFTER_BYE = 8  # grace period after the window closes, in case it was a reload
    FIRST = 120    # how long to wait for the first viewer

    def __init__(self, camera, worker, auto_quit):
        self.camera = camera
        self.worker = worker
        self.server = None
        self.auto_quit = auto_quit
        self.deadline = time.monotonic() + self.FIRST
        self._exiting = threading.Lock()

    def seen(self):
        self.deadline = time.monotonic() + self.IDLE

    def bye(self):
        self.deadline = time.monotonic() + self.AFTER_BYE

    def watch(self):
        while self.auto_quit:
            time.sleep(1)
            if time.monotonic() > self.deadline:
                print("Viewer closed, quitting.", flush=True)
                self.exit()
                return

    def release_camera(self):
        if self.worker:
            self.camera.stop.set()
            if hasattr(self.camera, "close"):
                self.camera.close()
            self.worker.join(timeout=5)

    def exit(self):
        if not self._exiting.acquire(blocking=False):
            return
        print("Releasing the camera...", flush=True)
        self.release_camera()
        threading.Thread(target=self.server.shutdown, daemon=True).start()


# ---- HTTP ----------------------------------------------------------------------------

def make_handler(frames, camera, life):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def _send(self, code, body, ctype, extra=None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Expose-Headers", "X-Seq")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def _json(self, obj, code=200):
            self._send(code, json.dumps(obj).encode(), "application/json")

        def do_GET(self):
            url = urlparse(self.path)
            life.seen()
            try:
                if url.path in ("/", "/index.html", "/viewer.html"):
                    with open(os.path.join(HERE, "viewer.html"), "rb") as f:
                        self._send(200, f.read(), "text/html; charset=utf-8")
                elif url.path == "/status":
                    with frames.cond:
                        body = {"bridge": True, "pid": os.getpid(), "control": camera.control, "state": frames.state,
                                "frames": frames.seq, "fps": round(frames.fps, 1), "log": list(frames.log)}
                    self._json(body)
                elif url.path == "/settings":
                    self._json({"control": camera.control, "settings": camera.snapshot()})
                elif url.path == "/next.jpg":
                    after = int(parse_qs(url.query).get("after", ["0"])[0] or 0)
                    seq, jpeg = frames.next_after(after, timeout=5)
                    if jpeg is None:
                        self._send(204, b"", "image/jpeg")
                    else:
                        self._send(200, jpeg, "image/jpeg", {"X-Seq": str(seq)})
                elif url.path == "/stream.mjpg":
                    self.stream()
                elif url.path == "/ping":
                    self._json({"ok": True})
                else:
                    self._send(404, b"not found", "text/plain")
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_POST(self):
            path = urlparse(self.path).path
            try:
                if path == "/bye":
                    life.bye()
                    return self._json({"ok": True})
                if path == "/quit":
                    self._json({"ok": True})
                    return threading.Thread(target=life.exit, daemon=True).start()
                life.seen()
                if path != "/cmd":
                    return self._send(404, b"not found", "text/plain")
                length = int(self.headers.get("Content-Length") or 0)
                try:
                    cmd = json.loads(self.rfile.read(length) or b"{}")
                except ValueError:
                    return self._json({"ok": False, "error": "bad json"}, 400)
                self._json(camera.submit(cmd))
            except (BrokenPipeError, ConnectionResetError):
                pass

        def stream(self):
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            seq = 0
            while True:
                seq, jpeg = frames.next_after(seq, timeout=5)
                if jpeg is None:
                    continue
                self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % len(jpeg))
                self.wfile.write(jpeg)
                self.wfile.write(b"\r\n")

    return Handler


def main():
    ap = argparse.ArgumentParser(description="Canon EOS USB live view and remote control")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1", help="0.0.0.0 to allow other devices on your network")
    ap.add_argument("--download", metavar="DIR", nargs="?", const=os.path.expanduser("~/Pictures/Live View"),
                    help="also copy every shot to this folder (default ~/Pictures/Live View); "
                         "without it, shots stay on the memory card only")
    ap.add_argument("--screen-off", action="store_true", help="let the camera turn its own screen off (smoother live view)")
    ap.add_argument("--view-only", action="store_true", help="use the gphoto2 command line tool, no controls")
    ap.add_argument("--gphoto2", default=shutil.which("gphoto2"), help="path to the gphoto2 binary (view-only mode)")
    ap.add_argument("--no-browser", action="store_true", help="don't open the viewer automatically")
    ap.add_argument("--install", action="store_true", help=f"build {APP_NAME}.app in ~/Applications (macOS)")
    ap.add_argument("--app", action="store_true", help=argparse.SUPPRESS)  # how the .app launches us
    args = ap.parse_args()

    if args.install:
        return install_app()
    url = f"http://localhost:{args.port}/"

    frames = Frames()
    if gp is not None and not args.view_only:
        camera = Controller(frames, keep_screen=not args.screen_off, download_dir=args.download)
    elif args.gphoto2:
        if gp is None:
            print("Camera controls are off. For focus/shutter/settings run:\n"
                  "    python3 -m pip install --user gphoto2\n", flush=True)
        camera = CliViewer(frames, args.gphoto2)
    else:
        camera = NoCamera()
        frames.note("no-gphoto2", "no camera driver. Run: python3 -m pip install --user gphoto2")

    life = Lifecycle(camera, None, auto_quit=args.app)
    try:
        server = http.server.ThreadingHTTPServer((args.host, args.port), make_handler(frames, camera, life))
    except OSError:
        if not args.app:
            raise
        # Something already has the port. A healthy copy of us: just open another window.
        # A stuck one: stop it and take over.
        if running_copy_is_healthy(url):
            open_viewer(url, app_window=True)
            return
        stop_stuck_copy(args.port)
        server = http.server.ThreadingHTTPServer((args.host, args.port), make_handler(frames, camera, life))
    server.daemon_threads = True
    life.server = server

    if hasattr(camera, "run"):
        life.worker = threading.Thread(target=camera.run, daemon=True)
        life.worker.start()
    threading.Thread(target=life.watch, daemon=True).start()

    print(f"Live view at {url}  (Ctrl+C to quit and give the camera back)", flush=True)
    if not args.no_browser:
        threading.Timer(0.6, open_viewer, args=(url, args.app)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
        life.release_camera()
    print("Camera released.", flush=True)
    os._exit(0)  # don't let a wedged USB call hold the process open on the way out


def running_copy_is_healthy(url):
    try:
        with urllib.request.urlopen(url + "status", timeout=3) as r:
            return json.load(r).get("bridge") is True
    except Exception:
        return False


def stop_stuck_copy(port):
    print("An earlier copy is stuck, stopping it.", flush=True)
    try:
        out = subprocess.run(["lsof", "-ti", f"tcp:{port}", "-sTCP:LISTEN"], capture_output=True, text=True).stdout
    except OSError:
        out = ""
    for pid in out.split():
        if pid.isdigit() and int(pid) != os.getpid():
            try:
                os.kill(int(pid), signal.SIGKILL)
            except OSError:
                pass
    time.sleep(1.5)


def open_viewer(url, app_window=False):
    """Open the viewer; on a Mac with Chrome, as its own app-style window."""
    if app_window and platform.system() == "Darwin":
        for chrome in ("/Applications/Google Chrome.app", os.path.expanduser("~/Applications/Google Chrome.app")):
            if os.path.exists(chrome):
                subprocess.run(["open", "-na", chrome, "--args", f"--app={url}"])
                return
    webbrowser.open(url)


def install_app():
    """Build ~/Applications/Live View.app, a double-clickable launcher for this bridge."""
    if platform.system() != "Darwin":
        sys.exit("--install builds a macOS app. On other systems run: python3 bridge.py")
    if gp is None:
        print("Note: camera controls need the gphoto2 package for this Python:\n"
              f"    {sys.executable} -m pip install --user gphoto2\n", flush=True)
    app = os.path.expanduser(f"~/Applications/{APP_NAME}.app")
    contents = os.path.join(app, "Contents")
    res = os.path.join(contents, "Resources")
    macos = os.path.join(contents, "MacOS")
    if os.path.exists(app):
        shutil.rmtree(app)
    os.makedirs(res)
    os.makedirs(macos)
    for name in ("bridge.py", "viewer.html"):
        shutil.copy2(os.path.join(HERE, name), res)

    launcher = os.path.join(macos, APP_NAME)
    with open(launcher, "w") as f:
        f.write("#!/bin/sh\n"
                'cd "$(dirname "$0")/../Resources" || exit 1\n'
                'mkdir -p "$HOME/Library/Logs"\n'
                # Start the bridge in the background and exit at once. macOS expects a
                # running app to answer it; a script that stays running can't, so a
                # second click would show "not responding". Each click runs this fresh.
                f'nohup "{sys.executable}" bridge.py --app >> "$HOME/Library/Logs/{APP_NAME}.log" 2>&1 &\n'
                "exit 0\n")
    os.chmod(launcher, 0o755)

    info = {
        "CFBundleName": APP_NAME,
        "CFBundleDisplayName": APP_NAME,
        "CFBundleIdentifier": "dev.brettboggs.liveview",
        "CFBundleExecutable": APP_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "10.13",
        "LSUIElement": True,  # no Dock icon of its own; the viewer window is the app
        "NSHighResolutionCapable": True,
    }
    icon = os.path.join(HERE, "icon.png")
    if os.path.exists(icon):
        iconset = os.path.join(res, "AppIcon.iconset")
        os.makedirs(iconset)
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = size * scale
                out = os.path.join(iconset, f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png")
                try:
                    subprocess.run(["sips", "-z", str(px), str(px), icon, "--out", out],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except OSError:
                    pass
        try:
            made = subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(res, "AppIcon.icns")]).returncode == 0
        except OSError:
            made = False
        if made:
            info["CFBundleIconFile"] = "AppIcon"
        shutil.rmtree(iconset, ignore_errors=True)
    with open(os.path.join(contents, "Info.plist"), "wb") as f:
        plistlib.dump(info, f)

    subprocess.run(["touch", app])
    print(f"Built {app}\n"
          "Open it from Launchpad or Spotlight, or drag it from the Finder window into your Dock.\n"
          f"Problems? See ~/Library/Logs/{APP_NAME}.log", flush=True)
    subprocess.run(["open", "-R", app])


if __name__ == "__main__":
    main()
