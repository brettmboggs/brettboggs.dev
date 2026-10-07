#!/usr/bin/env python3
"""Live view for a Canon EOS over USB.

Pulls the live view feed out of the camera with gphoto2 and serves it, plus
the viewer page, on http://localhost:8765. Standard library only.

    python3 bridge.py                 # open the viewer in your browser
    python3 bridge.py --host 0.0.0.0  # also reachable from a phone/iPad on your Wi-Fi

Endpoints: /            the viewer
           /next.jpg    the next live view frame (waits for it)
           /stream.mjpg plain MJPEG, for OBS, VLC, etc.
           /status      JSON health
"""
import argparse
import http.server
import json
import os
import platform
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from collections import deque
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
SOI, EOI = b"\xff\xd8", b"\xff\xd9"


class Frames:
    """Latest JPEG frame, shared between the camera reader and HTTP clients."""

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
    # ptpcamerad), which stops gphoto2 from claiming the USB device.
    if platform.system() == "Darwin":
        subprocess.run(["pkill", "-f", "ptpcamera"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-f", "PTPCamera"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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


def camera_loop(frames, gphoto2):
    hint_shown = False
    while True:
        release_camera_on_macos()
        frames.note("connecting", "starting live view")
        try:
            proc = subprocess.Popen(
                [gphoto2, "--stdout", "--capture-movie"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0,
            )
        except OSError as exc:
            frames.note("error", f"could not run gphoto2: {exc}")
            time.sleep(3)
            continue

        def drain_stderr():
            for raw in proc.stderr:
                line = raw.decode("utf-8", "replace").strip()
                if line and not line.startswith("Capturing preview frames"):
                    frames.note(frames.state, line)

        threading.Thread(target=drain_stderr, daemon=True).start()

        buf = bytearray()
        fd = proc.stdout.fileno()
        while True:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            buf += chunk
            split_jpegs(buf, frames.put)
            if len(buf) > 8 << 20:  # garbage, not a stream we understand
                buf.clear()

        code = proc.wait()
        frames.note("disconnected", f"gphoto2 exited ({code}), retrying in 2s")
        if not hint_shown:
            hint_shown = True
            print(
                "\n  Not getting frames? Check that:\n"
                "   - the camera is on, USB cable in, and not asleep (Auto power off: Disable)\n"
                "   - EOS Utility, Image Capture, Photos and Lightroom are all closed\n"
                "   - `gphoto2 --auto-detect` lists the camera\n",
                flush=True,
            )
        time.sleep(2)


def make_handler(frames):
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

        def do_GET(self):
            url = urlparse(self.path)
            try:
                if url.path in ("/", "/index.html", "/viewer.html"):
                    with open(os.path.join(HERE, "viewer.html"), "rb") as f:
                        self._send(200, f.read(), "text/html; charset=utf-8")
                elif url.path == "/status":
                    with frames.cond:
                        body = {"bridge": True, "state": frames.state, "frames": frames.seq,
                                "fps": round(frames.fps, 1), "log": list(frames.log)}
                    self._send(200, json.dumps(body).encode(), "application/json")
                elif url.path == "/next.jpg":
                    after = int(parse_qs(url.query).get("after", ["0"])[0] or 0)
                    seq, jpeg = frames.next_after(after, timeout=5)
                    if jpeg is None:
                        self._send(204, b"", "image/jpeg")
                    else:
                        self._send(200, jpeg, "image/jpeg", {"X-Seq": str(seq)})
                elif url.path == "/stream.mjpg":
                    self.stream()
                else:
                    self._send(404, b"not found", "text/plain")
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
    ap = argparse.ArgumentParser(description="Canon EOS USB live view bridge")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1", help="0.0.0.0 to allow other devices on your network")
    ap.add_argument("--gphoto2", default=shutil.which("gphoto2"), help="path to the gphoto2 binary")
    ap.add_argument("--no-browser", action="store_true", help="don't open the viewer automatically")
    args = ap.parse_args()

    frames = Frames()
    if args.gphoto2:
        threading.Thread(target=camera_loop, args=(frames, args.gphoto2), daemon=True).start()
    else:
        frames.note("no-gphoto2", "gphoto2 not found. Install it (macOS: brew install gphoto2). "
                    "The viewer still works with webcam / capture card sources.")

    server = http.server.ThreadingHTTPServer((args.host, args.port), make_handler(frames))
    server.daemon_threads = True
    url = f"http://localhost:{args.port}/"
    print(f"Live view at {url}  (Ctrl+C to quit)", flush=True)
    if not args.no_browser:
        threading.Timer(0.6, webbrowser.open, args=(url,)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
        sys.exit(0)


if __name__ == "__main__":
    main()
