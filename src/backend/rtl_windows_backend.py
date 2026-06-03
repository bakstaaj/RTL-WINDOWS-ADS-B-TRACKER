#!/usr/bin/env python3
"""Local backend API for the RTL-Windows-ADS-B-Tracker application.

This initial service owns ADS-B process startup and provides a stable API
surface for the future web UI. It intentionally uses only Python's standard
library so the first Windows runtime has no third-party Python dependency.

Startup rule enforced here:
  1. Run the native device-role probe sequentially.
  2. Resolve EEPROM serial 00001090 to this session's numeric ADS-B index.
  3. Start Dump1090 using that numeric index and the validated RF profile.
"""

from __future__ import annotations

import argparse
import json
import logging
import shutil
import signal
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen

LOG = logging.getLogger("rtl_windows_backend")
ADSB_SERIAL = "00001090"
AUDIO_SERIAL = "00000162"


def windows_path(path: Path) -> str:
    """Convert an MSYS path to a Windows path for native Windows executables."""
    cygpath = shutil.which("cygpath")
    if not cygpath:
        raise RuntimeError("cygpath is required when running this backend from MSYS2.")
    result = subprocess.run(
        [cygpath, "-w", str(path)],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result.stdout.strip()


class DecoderManager:
    """Own the serial-role mapping and the child Dump1090 decoder process."""

    def __init__(self, root: Path, dump_http_port: int) -> None:
        self.root = root
        self.dump_http_port = dump_http_port
        self.probe = root / "dist" / "native-windows" / "rtl_dual_device_probe.exe"
        self.dump1090 = root / "dist" / "third_party" / "dump1090" / "dump1090.exe"
        self.airport_db = root / "dist" / "third_party" / "dump1090" / "airport-codes.csv"
        self.runtime_dir = root / "runtime" / "settings"
        self.config = self.runtime_dir / "dump1090_backend_runtime.cfg"
        self.log_path = self.runtime_dir / "dump1090_backend.log"
        self.process: subprocess.Popen[str] | None = None
        self.log_handle: Any = None
        self.roles: dict[str, Any] | None = None
        self.lock = threading.RLock()
        self.started_at: float | None = None
        self.last_error: str | None = None

    @property
    def decoder_json_url(self) -> str:
        return f"http://127.0.0.1:{self.dump_http_port}/data/aircraft.json"

    def check_runtime_files(self) -> None:
        for path in (self.probe, self.dump1090, self.airport_db):
            if not path.exists():
                raise RuntimeError(f"Required runtime file is missing: {path}")

    def resolve_roles(self) -> dict[str, Any]:
        self.check_runtime_files()
        completed = subprocess.run(
            [windows_path(self.probe), "--json"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        mapping = json.loads(completed.stdout.strip())
        if not mapping.get("ok"):
            raise RuntimeError(f"Device-role probe reported failure: {mapping}")
        if mapping.get("adsb", {}).get("serial") != ADSB_SERIAL:
            raise RuntimeError(f"ADS-B serial {ADSB_SERIAL} was not resolved: {mapping}")
        if mapping.get("audio", {}).get("serial") != AUDIO_SERIAL:
            raise RuntimeError(f"Audio serial {AUDIO_SERIAL} was not resolved: {mapping}")
        self.roles = mapping
        return mapping

    def write_config(self) -> None:
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        airport_path = windows_path(self.airport_db)
        self.config.write_text(
            "\n".join(
                [
                    "# Generated application runtime configuration; excluded from Git.",
                    "aircrafts = NUL",
                    f"airports = {airport_path}",
                    "homepos = 38.7467,-105.1783",
                    "location = no",
                    "logfile = NUL",
                    "silent = true",
                    "error-correct1 = true",
                    "error-correct2 = true",
                    "agc = false",
                    "gain = 48.8",
                    "freq = 1090.0M",
                    "phase-enhance = false",
                    "samplerate = 2M",
                    "DC-filter = true",
                    "measure-noise = true",
                    "rtlsdr-calibrate = false",
                    "rtlsdr-ppm = 0",
                    f"net-http-port = {self.dump_http_port}",
                    f"net-ri-port = {self.dump_http_port + 1}",
                    f"net-ro-port = {self.dump_http_port + 2}",
                    f"net-sbs-port = {self.dump_http_port + 3}",
                    "web-send-rssi = true",
                    "",
                ]
            ),
            encoding="utf-8",
            newline="\n",
        )

    def is_running(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def query_aircraft(self, timeout: float = 1.5) -> dict[str, Any]:
        with urlopen(self.decoder_json_url, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))

    def start(self) -> dict[str, Any]:
        with self.lock:
            if self.is_running():
                return self.status()
            self.last_error = None
            try:
                mapping = self.resolve_roles()
                adsb_index = int(mapping["adsb"]["index"])
                self.write_config()
                self.runtime_dir.mkdir(parents=True, exist_ok=True)
                self.log_handle = self.log_path.open("a", encoding="utf-8", newline="\n")
                command = [
                    windows_path(self.dump1090),
                    "--config",
                    windows_path(self.config),
                    "--device",
                    str(adsb_index),
                    "--net",
                ]
                LOG.info("Starting Dump1090 for ADS-B serial %s at index %s", ADSB_SERIAL, adsb_index)
                self.process = subprocess.Popen(
                    command,
                    cwd=windows_path(self.dump1090.parent),
                    stdout=self.log_handle,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                self.started_at = time.time()

                deadline = time.time() + 15
                while time.time() < deadline:
                    if self.process.poll() is not None:
                        raise RuntimeError(
                            f"Dump1090 exited during startup with code {self.process.returncode}; "
                            f"see {self.log_path}."
                        )
                    try:
                        self.query_aircraft()
                        return self.status()
                    except (URLError, TimeoutError, json.JSONDecodeError):
                        time.sleep(0.25)
                raise RuntimeError("Dump1090 did not expose its JSON endpoint during startup.")
            except Exception as exc:
                self.last_error = str(exc)
                self.stop()
                raise

    def stop(self) -> None:
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                LOG.info("Stopping Dump1090")
                self.process.terminate()
                try:
                    self.process.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=3)
            self.process = None
            self.started_at = None
            if self.log_handle is not None:
                self.log_handle.close()
                self.log_handle = None

    def status(self) -> dict[str, Any]:
        running = self.is_running()
        decoder: dict[str, Any] = {
            "running": running,
            "profile": {
                "frequency_hz": 1090000000,
                "sample_rate_sps": 2000000,
                "gain_db": 48.8,
            },
            "json_url_internal": self.decoder_json_url,
        }
        if running:
            try:
                aircraft_json = self.query_aircraft()
                decoder["messages"] = int(aircraft_json.get("messages", 0))
                decoder["aircraft_count"] = len(aircraft_json.get("aircraft", []))
                decoder["json_ready"] = True
            except Exception as exc:
                decoder["json_ready"] = False
                decoder["query_error"] = str(exc)
        else:
            decoder["json_ready"] = False

        return {
            "ok": True,
            "service": "RTL-Windows-ADS-B-Tracker",
            "receiver_roles": self.roles,
            "decoder": decoder,
            "last_error": self.last_error,
        }


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "RTLWindowsADSBBackend/0.1"

    @property
    def manager(self) -> DecoderManager:
        return self.server.manager  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: Any) -> None:
        LOG.info("%s - %s", self.address_string(), format % args)

    def send_json(self, code: int, payload: Any) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        try:
            if self.path in ("/", "/health"):
                self.send_json(HTTPStatus.OK, {"ok": True, "service": "RTL-Windows-ADS-B-Tracker"})
            elif self.path == "/api/status":
                self.send_json(HTTPStatus.OK, self.manager.status())
            elif self.path == "/api/receiver-roles":
                if self.manager.roles is None:
                    self.manager.resolve_roles()
                self.send_json(HTTPStatus.OK, self.manager.roles)
            elif self.path == "/api/aircraft":
                if not self.manager.is_running():
                    self.send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"ok": False, "error": "decoder_not_running"})
                else:
                    self.send_json(HTTPStatus.OK, self.manager.query_aircraft())
            else:
                self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not_found"})
        except Exception as exc:
            LOG.exception("GET request failed")
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": str(exc)})

    def do_POST(self) -> None:
        try:
            if self.path == "/api/decoder/start":
                self.send_json(HTTPStatus.OK, self.manager.start())
            elif self.path == "/api/decoder/stop":
                self.manager.stop()
                self.send_json(HTTPStatus.OK, self.manager.status())
            else:
                self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "not_found"})
        except Exception as exc:
            LOG.exception("POST request failed")
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": str(exc)})


def main() -> int:
    parser = argparse.ArgumentParser(description="RTL-Windows-ADS-B-Tracker local backend API")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--dump-http-port", type=int, default=18080)
    parser.add_argument("--autostart", action="store_true", help="Start ADS-B decoder on backend startup.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    root = Path(__file__).resolve().parents[2]
    manager = DecoderManager(root, args.dump_http_port)
    server = ThreadingHTTPServer((args.host, args.port), ApiHandler)
    server.manager = manager  # type: ignore[attr-defined]

    def shutdown_handler(signum: int, frame: Any) -> None:
        del signum, frame
        manager.stop()
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    try:
        if args.autostart:
            manager.start()
        LOG.info("Backend API listening at http://%s:%s", args.host, args.port)
        server.serve_forever()
    except KeyboardInterrupt:
        LOG.info("Backend shutdown requested")
    finally:
        manager.stop()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
