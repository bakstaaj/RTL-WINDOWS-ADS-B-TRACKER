#!/usr/bin/env python3
"""Windows implementation of the published RTL-Pi-ADS-B-Tracker browser API.

This module deliberately leaves rtl_windows_backend.py intact.  It reuses the
validated Windows receiver-role, Dump1090, RTL-FM live-audio and FAA catalog
foundation while presenting the endpoint contract expected by the Pi UI.

Current port baseline:
  * live ADS-B map and aircraft list
  * receiver location and airband scan radius persistence
  * NOAA fixed/saved live listening plus seven-channel level survey
  * nearby FAA airband listing and AM capture
  * background AM scan using RMS-level activity evidence

RF-SNR equivalence, saved Pi trail collection, AirLabs and the simulated
diagnostic scanner remain explicit follow-on port items.
"""

from __future__ import annotations

from array import array
import argparse
import io
import json
import logging
from logging.handlers import RotatingFileHandler
import math
import mimetypes
import signal
import threading
import time
import urllib.request
import urllib.parse
import urllib.error
import wave
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from faa_airband_catalog import AirbandCatalog
from rtl_windows_backend import (
    ADSB_SERIAL,
    AUDIO_SERIAL,
    AIRBAND_LIVE_AUDIO_PROFILE,
    NOAA_PROFILE,
    AudioManager,
    DecoderManager,
    SettingsStore,
)

LOG = logging.getLogger("rtl_windows_pi_port_backend")
NOAA_FREQUENCIES = [
    162400000, 162425000, 162450000, 162475000,
    162500000, 162525000, 162550000,
]
DEFAULT_RADIUS_MILES = 100.0
DEFAULT_AIRBAND_ACTIVITY_RMS = 650.0


class PiPortSettingsStore(SettingsStore):
    """Persist Pi-facing application settings in the existing runtime settings file."""

    def __init__(self, path: Path) -> None:
        self.airband_radius_miles = DEFAULT_RADIUS_MILES
        self.noaa_frequency_hz = int(NOAA_PROFILE["frequency_hz"])
        self.noaa_station = f"Configured NOAA — {self.noaa_frequency_hz / 1_000_000:.3f} MHz"
        super().__init__(path)
        if path.exists():
            try:
                loaded = json.loads(path.read_text(encoding="utf-8"))
                self.airband_radius_miles = self._validate_radius(
                    loaded.get("airband_radius_miles", DEFAULT_RADIUS_MILES)
                )
                selection = loaded.get("noaa_selection")
                if isinstance(selection, dict) and int(selection.get("frequency_hz", 0)) in NOAA_FREQUENCIES:
                    self.noaa_frequency_hz = int(selection["frequency_hz"])
                    self.noaa_station = str(selection.get("station") or self.noaa_station)
            except Exception as exc:
                LOG.warning("Unable to read Pi-port extended settings: %s", exc)

    @staticmethod
    def _validate_radius(value: Any) -> float:
        radius = float(value)
        if not 0.0 < radius <= 500.0:
            raise ValueError("Airband radius must be greater than 0 and no more than 500 miles.")
        return round(radius, 1)

    def _persist_port_settings(self) -> None:
        with self.lock:
            payload = {
                "receiver_location": self.receiver_location(),
                "airband_radius_miles": self.airband_radius_miles,
                "noaa_selection": {
                    "frequency_hz": self.noaa_frequency_hz,
                    "station": self.noaa_station,
                },
            }
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(self.path.suffix + ".tmp")
            temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8", newline="\n")
            temporary.replace(self.path)

    def pi_location(self) -> dict[str, Any]:
        location = self.receiver_location()
        return {
            "name": str(location.get("label") or "Receiver"),
            "latitude": float(location["latitude"]),
            "longitude": float(location["longitude"]),
            "airband_radius_miles": self.airband_radius_miles,
        }

    def save_pi_location(self, payload: dict[str, Any]) -> dict[str, Any]:
        native = {
            "label": payload.get("name", payload.get("label", "Receiver")),
            "latitude": payload.get("latitude"),
            "longitude": payload.get("longitude"),
        }
        self.update_receiver_location(native)
        if payload.get("airband_radius_miles") not in (None, ""):
            self.airband_radius_miles = self._validate_radius(payload["airband_radius_miles"])
        self._persist_port_settings()
        return self.pi_location()

    def save_airband_radius(self, value: Any) -> dict[str, Any]:
        self.airband_radius_miles = self._validate_radius(value)
        self._persist_port_settings()
        return self.pi_location()

    def save_noaa_selection(self, frequency_hz: int, station: str) -> None:
        self.noaa_frequency_hz = int(frequency_hz)
        self.noaa_station = str(station)
        self._persist_port_settings()


def rms_from_wav(content: bytes) -> float:
    with wave.open(io.BytesIO(content), "rb") as wav_file:
        frames = wav_file.readframes(wav_file.getnframes())
    samples = array("h")
    samples.frombytes(frames[: len(frames) - (len(frames) % 2)])
    if not samples:
        return 0.0
    return math.sqrt(sum(value * value for value in samples) / len(samples))


def pcm_from_wav(content: bytes) -> tuple[bytes, int]:
    with wave.open(io.BytesIO(content), "rb") as wav_file:
        return wav_file.readframes(wav_file.getnframes()), wav_file.getframerate()


def make_wav(pcm: bytes, rate: int) -> bytes:
    output = io.BytesIO()
    with wave.open(output, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(rate)
        wav_file.writeframes(pcm)
    return output.getvalue()


class AudioOperations:
    """Use validated rolling Windows live audio transport for bounded Pi-style operations."""

    def __init__(self, audio: AudioManager) -> None:
        self.audio = audio
        self.lock = threading.RLock()
        self.noaa_live_active = False

    def _capture_profile(self, profile: dict[str, Any], seconds: float, channel: dict[str, Any] | None = None) -> bytes:
        with self.lock:
            if self.noaa_live_active or self.audio.live_is_running() or self.audio.is_running():
                raise RuntimeError("Audio receiver is already in use.")
            self.audio._start_live_process(dict(profile), channel)
            sequence = 0
            pcm_parts: list[bytes] = []
            rate = int(profile["sample_rate_hz"])
            needed = max(1, math.ceil(seconds / self.audio.live_chunk_seconds))
            try:
                for _ in range(needed):
                    chunk = self.audio.next_live_wav(sequence, timeout_seconds=3.0)
                    if chunk is None:
                        raise RuntimeError("Audio capture ended before samples were received.")
                    sequence, wav_content = chunk
                    pcm, rate = pcm_from_wav(wav_content)
                    pcm_parts.append(pcm)
            finally:
                self.audio.stop_live()
            return make_wav(b"".join(pcm_parts), rate)

    def live_noaa_start(self, settings: PiPortSettingsStore) -> dict[str, Any]:
        with self.lock:
            if self.audio.live_is_running():
                if self.noaa_live_active:
                    return {"started": False, "already_running": True}
                raise RuntimeError("Audio receiver is in use by Airband scanning or capture.")
            profile = dict(NOAA_PROFILE)
            profile["frequency_hz"] = settings.noaa_frequency_hz
            profile["rtl_fm_mode"] = "fm"
            result = self.audio._start_live_process(profile, None)
            self.noaa_live_active = True
            return result

    def live_noaa_stop(self) -> dict[str, Any]:
        with self.lock:
            result = self.audio.stop_live()
            self.noaa_live_active = False
            return result

    def capture_noaa(self, settings: PiPortSettingsStore, seconds: int) -> bytes:
        profile = dict(NOAA_PROFILE)
        profile["frequency_hz"] = settings.noaa_frequency_hz
        profile["rtl_fm_mode"] = "fm"
        return self._capture_profile(profile, seconds)

    def capture_airband(self, channel: dict[str, Any], seconds: int) -> bytes:
        profile = dict(AIRBAND_LIVE_AUDIO_PROFILE)
        profile["frequency_hz"] = int(channel["frequency_hz"])
        profile["rtl_fm_mode"] = "am"
        return self._capture_profile(profile, seconds, channel)

    def survey_noaa(self, settings: PiPortSettingsStore) -> dict[str, Any]:
        results = []
        for frequency_hz in NOAA_FREQUENCIES:
            profile = dict(NOAA_PROFILE)
            profile["frequency_hz"] = frequency_hz
            profile["rtl_fm_mode"] = "fm"
            wav_content = self._capture_profile(profile, 1.0)
            results.append({"frequency_hz": frequency_hz, "rms_sample": round(rms_from_wav(wav_content), 2)})
        results.sort(key=lambda row: row["rms_sample"], reverse=True)
        best = results[0]
        station = f"AUTO SELECT — {best['frequency_hz'] / 1_000_000:.3f} MHz"
        settings.save_noaa_selection(int(best["frequency_hz"]), station)
        return {"best_frequency_hz": best["frequency_hz"], "channels": results, "station": station}


class AirbandScanPort:
    """Simple Windows background AM sampler exposed through the Pi scan status contract."""

    def __init__(self, audio_ops: AudioOperations, settings: PiPortSettingsStore, catalog: AirbandCatalog) -> None:
        self.audio_ops = audio_ops
        self.settings = settings
        self.catalog = catalog
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None
        self.state: dict[str, Any] = {
            "airband_scan_running": False,
            "airband_scan_state": "stopped",
            "airband_scan_cycles": 0,
            "airband_channels_scanned": 0,
            "airband_current_channel": None,
            "airband_last_measurement_dbfs": None,
            "airband_last_signal_snr_db": None,
            "airband_last_detection": None,
            "airband_best_candidate": None,
            "airband_scan_scope": None,
            "airband_scan_error": None,
        }
        self.last_audio: bytes | None = None
        self.best_audio: bytes | None = None
        self.best_rms = 0.0

    @staticmethod
    def _pi_channel(native: dict[str, Any]) -> dict[str, Any]:
        return {
            "frequency_mhz": native.get("frequency_mhz"),
            "frequency_hz": native.get("frequency_hz"),
            "use": native.get("frequency_use", ""),
            "airport_id": native.get("serviced_facility", ""),
            "airport_name": native.get("serviced_facility_name", ""),
            "facility_type": native.get("frequency_use", ""),
            "distance_miles": native.get("distance_miles"),
            "_native": native,
        }

    def nearby(self) -> dict[str, Any]:
        raw = self.catalog.query(self.settings.receiver_location(), self.settings.airband_radius_miles, 200)
        unique: dict[int, dict[str, Any]] = {}
        for native in raw.get("channels", []):
            freq = int(native["frequency_hz"])
            if freq not in unique:
                unique[freq] = self._pi_channel(native)
        channels = list(unique.values())
        return {
            "data_available": bool(raw.get("catalog_available")),
            "receiver_location": self.settings.pi_location(),
            "radius_miles": self.settings.airband_radius_miles,
            "duplicate_records_removed": max(0, int(raw.get("matching_channel_count", len(channels))) - len(channels)),
            "channel_count": len(channels),
            "channels": channels,
        }

    def _select_channels(self, scope: str) -> list[dict[str, Any]]:
        channels = self.nearby()["channels"]
        if scope == "all" or scope == "continuous":
            return channels
        priority = [
            channel for channel in channels
            if any(token in str(channel.get("use", "")).upper() for token in ("AWOS", "ASOS", "ATIS", "CTAF", "UNICOM"))
        ]
        return priority or channels

    def status(self) -> dict[str, Any]:
        with self.lock:
            return dict(self.state)

    def start(self, scope: str) -> dict[str, Any]:
        with self.lock:
            if self.state["airband_scan_running"]:
                return {"started": False, "channel_count": 0, **self.status()}
        channels = self._select_channels(scope)
        if not channels:
            raise RuntimeError("No nearby Airband channels are available for scanning.")
        self.stop_event.clear()
        with self.lock:
            self.state.update({
                "airband_scan_running": True,
                "airband_scan_state": "starting",
                "airband_scan_cycles": 0,
                "airband_channels_scanned": 0,
                "airband_current_channel": None,
                "airband_last_detection": None,
                "airband_scan_scope": scope,
                "airband_scan_error": None,
            })
        self.thread = threading.Thread(target=self._run, args=(channels,), daemon=True, name="pi-port-airband-scan")
        self.thread.start()
        return {"started": True, "channel_count": len(channels), "scan_scope": scope, **self.status()}

    def stop(self) -> dict[str, Any]:
        self.stop_event.set()
        thread = self.thread
        if thread and thread is not threading.current_thread():
            thread.join(timeout=4)
        with self.lock:
            self.state["airband_scan_running"] = False
            self.state["airband_scan_state"] = "stopped"
        return {"stopped": True, **self.status()}

    def _run(self, channels: list[dict[str, Any]]) -> None:
        try:
            while not self.stop_event.is_set():
                with self.lock:
                    self.state["airband_scan_cycles"] += 1
                    self.state["airband_scan_state"] = "searching"
                for channel in channels:
                    if self.stop_event.is_set():
                        break
                    try:
                        wav_content = self.audio_ops.capture_airband(channel["_native"], 0.5)
                        rms = rms_from_wav(wav_content)
                    except Exception as exc:
                        if self.stop_event.is_set():
                            break
                        with self.lock:
                            self.state["airband_scan_error"] = str(exc)
                        time.sleep(0.1)
                        continue
                    candidate = {
                        "channel": {k: v for k, v in channel.items() if k != "_native"},
                        "audio_rms_sample": round(rms, 2),
                        "rf_estimated_snr_db": None,
                        "observed_utc": int(time.time()),
                        "audio_url": "/api/airband/scan/best_audio.wav",
                    }
                    with self.lock:
                        self.state["airband_channels_scanned"] += 1
                        self.state["airband_current_channel"] = candidate["channel"]
                        self.state["airband_last_measurement_dbfs"] = round(rms, 2)
                        self.state["airband_last_signal_snr_db"] = None
                        if rms > self.best_rms:
                            self.best_rms = rms
                            self.best_audio = wav_content
                            self.state["airband_best_candidate"] = candidate
                        if rms >= DEFAULT_AIRBAND_ACTIVITY_RMS:
                            self.last_audio = wav_content
                            self.state["airband_last_detection"] = {
                                **candidate,
                                "threshold_rms_sample": DEFAULT_AIRBAND_ACTIVITY_RMS,
                                "audio_url": "/api/airband/scan/last_audio.wav",
                            }
                            self.state["airband_scan_state"] = "activity_detected"
                time.sleep(0.05)
        except Exception as exc:
            with self.lock:
                self.state["airband_scan_error"] = str(exc)
                self.state["airband_scan_state"] = "error"
        finally:
            with self.lock:
                self.state["airband_scan_running"] = False
                if self.state["airband_scan_state"] != "error":
                    self.state["airband_scan_state"] = "stopped"


class TrailHistoryCollector:
    # Pi-compatible persisted trail history collected by the Windows API process.
    def __init__(
        self,
        manager: DecoderManager,
        settings_dir: Path,
        sample_seconds: float = 2.0,
        retention_minutes: int = 240,
        max_points_per_aircraft: int = 7200,
    ) -> None:
        self.manager = manager
        self.history_path = settings_dir / "aircraft_trails_history.json"
        self.control_path = settings_dir / "aircraft_trails_control.json"
        self.sample_seconds = sample_seconds
        self.retention_minutes = retention_minutes
        self.max_points_per_aircraft = max_points_per_aircraft
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None
        self.trails = self._load_trails()
        self.cleared_utc_ms = self._clear_watermark_ms()

    @staticmethod
    def _read_json(path: Path) -> dict[str, Any]:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            return {}

    def _clear_watermark_ms(self) -> int:
        try:
            return int(self._read_json(self.control_path).get("cleared_utc_ms", 0))
        except (TypeError, ValueError):
            return 0

    def _load_trails(self) -> dict[str, list[dict[str, Any]]]:
        data = self._read_json(self.history_path)
        trails = data.get("trails", {})
        return trails if isinstance(trails, dict) else {}

    def _payload_locked(self) -> dict[str, Any]:
        return {
            "updated_utc": int(time.time()),
            "retention_minutes": self.retention_minutes,
            "source": "windows_dump1090_background_collector",
            "cleared_utc_ms": self.cleared_utc_ms,
            "trails": self.trails,
        }

    def _write_locked(self) -> None:
        self.history_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.history_path.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(self._payload_locked(), separators=(",", ":")) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        temporary.replace(self.history_path)

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return json.loads(json.dumps(self._payload_locked()))

    def clear(self) -> dict[str, Any]:
        with self.lock:
            self.cleared_utc_ms = int(time.time() * 1000)
            self.trails = {}
            self.control_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.control_path.with_suffix(".json.tmp")
            temporary.write_text(
                json.dumps(
                    {"cleared_utc_ms": self.cleared_utc_ms, "cleared_utc": int(time.time())},
                    indent=2,
                ) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            temporary.replace(self.control_path)
            self._write_locked()
            return {
                "cleared": True,
                "cleared_utc_ms": self.cleared_utc_ms,
                "message": "Stored trail history cleared.",
            }

    def _prune_locked(self, now_ms: int) -> None:
        cutoff = now_ms - self.retention_minutes * 60 * 1000 if self.retention_minutes > 0 else 0
        for key in list(self.trails):
            points = self.trails.get(key, [])
            kept = [
                point for point in points
                if isinstance(point, dict) and (not cutoff or int(point.get("time", 0)) >= cutoff)
            ][-self.max_points_per_aircraft:]
            if kept:
                self.trails[key] = kept
            else:
                self.trails.pop(key, None)

    @staticmethod
    def _altitude(aircraft: dict[str, Any]) -> float | None:
        value = aircraft.get("alt_baro")
        if value is None:
            value = aircraft.get("altitude")
        if value is None:
            value = aircraft.get("alt_geom")
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    def collect_once(self) -> None:
        if not self.manager.is_running():
            return
        try:
            payload = self.manager.query_aircraft()
        except Exception as exc:
            LOG.debug("Trail collector could not read aircraft data: %s", exc)
            return
        rows = payload.get("aircraft", [])
        if not isinstance(rows, list):
            return
        now_ms = int(time.time() * 1000)
        changed = False
        with self.lock:
            latest_clear = self._clear_watermark_ms()
            if latest_clear > self.cleared_utc_ms:
                self.trails = {}
                self.cleared_utc_ms = latest_clear
                changed = True
            for aircraft in rows:
                if not isinstance(aircraft, dict):
                    continue
                key = str(aircraft.get("hex") or "").strip().lower()
                if not key:
                    continue
                try:
                    latitude = float(aircraft["lat"])
                    longitude = float(aircraft["lon"])
                except (KeyError, TypeError, ValueError):
                    continue
                point = {
                    "lat": latitude,
                    "lon": longitude,
                    "altitude": self._altitude(aircraft),
                    "time": now_ms,
                    "flight": str(aircraft.get("flight") or "").strip(),
                    "track": aircraft.get("track", aircraft.get("heading")),
                }
                points = self.trails.setdefault(key, [])
                previous = points[-1] if points else None
                if previous and previous.get("lat") == latitude and previous.get("lon") == longitude:
                    continue
                points.append(point)
                changed = True
            self._prune_locked(now_ms)
            if changed:
                self._write_locked()

    def _worker(self) -> None:
        while not self.stop_event.is_set():
            self.collect_once()
            self.stop_event.wait(self.sample_seconds)

    def start(self) -> None:
        if self.thread and self.thread.is_alive():
            return
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._worker, daemon=True, name="windows-trail-history")
        self.thread.start()
        LOG.info(
            "Windows trail collector started: every %.1f seconds, retention %s minutes",
            self.sample_seconds,
            self.retention_minutes,
        )

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread and self.thread is not threading.current_thread():
            self.thread.join(timeout=self.sample_seconds + 1.0)


class AirLabsIntegration:
    # Pi-compatible AirLabs route enrichment and private two-hour route cache.
    CACHE_TTL_SECONDS = 7200

    def __init__(self, settings_dir: Path) -> None:
        self.settings_dir = settings_dir
        self.key_path = settings_dir / "airlabs_api.json"
        self.cache_path = settings_dir / "airlabs_route_cache.json"
        self.lock = threading.RLock()

    @staticmethod
    def _read_json(path: Path) -> dict[str, Any]:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            return payload if isinstance(payload, dict) else {}
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            return {}

    @staticmethod
    def _write_private_json(path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8", newline="\n")
        try:
            temporary.chmod(0o600)
        except OSError:
            pass
        temporary.replace(path)
        try:
            path.chmod(0o600)
        except OSError:
            pass

    def _api_key(self) -> str:
        return str(self._read_json(self.key_path).get("api_key", "")).strip()

    def _cache_entries(self) -> dict[str, Any]:
        entries = self._read_json(self.cache_path).get("entries", {})
        return entries if isinstance(entries, dict) else {}

    def _active_cache_count(self) -> int:
        now = int(time.time())
        return sum(
            1 for entry in self._cache_entries().values()
            if isinstance(entry, dict)
            and now - int(entry.get("cached_utc", 0)) < self.CACHE_TTL_SECONDS
        )

    def status(self) -> dict[str, Any]:
        key = self._api_key()
        return {
            "provider": "AirLabs",
            "diagnostic_only": True,
            "configured": bool(key),
            "key_hint": ("Ending in " + key[-4:]) if key else None,
            "settings_file": self.key_path.name,
            "route_cache_entries": self._active_cache_count(),
            "cache_ttl_seconds": self.CACHE_TTL_SECONDS,
        }

    def save_key(self, api_key: str) -> dict[str, Any]:
        key = str(api_key or "").strip()
        with self.lock:
            if not key:
                try:
                    self.key_path.unlink()
                except FileNotFoundError:
                    pass
                return self.status()
            self._write_private_json(
                self.key_path,
                {"api_key": key, "updated_utc": int(time.time())},
            )
            reread = self.status()
            if not reread["configured"]:
                raise RuntimeError("AirLabs key was written but could not be read back.")
            return reread

    def clear_cache(self) -> dict[str, Any]:
        with self.lock:
            try:
                self.cache_path.unlink()
            except FileNotFoundError:
                pass
        return {
            "provider": "AirLabs",
            "cleared": True,
            "route_cache_entries": 0,
            "cache_ttl_seconds": self.CACHE_TTL_SECONDS,
        }

    @staticmethod
    def _clean_callsign(value: str) -> str:
        return "".join(character for character in str(value or "").upper().strip() if character.isalnum())

    def _load_cached(self, callsign: str) -> dict[str, Any] | None:
        with self.lock:
            entry = self._cache_entries().get(callsign)
        if not isinstance(entry, dict):
            return None
        cached_utc = int(entry.get("cached_utc", 0))
        age_seconds = max(0, int(time.time()) - cached_utc)
        if age_seconds >= self.CACHE_TTL_SECONDS:
            return None
        result = entry.get("result")
        if not isinstance(result, dict) or not result.get("matched"):
            return None
        cached_result = dict(result)
        cached_result.update(
            {
                "cache_hit": True,
                "cache_age_seconds": age_seconds,
                "cache_ttl_seconds": self.CACHE_TTL_SECONDS,
                "message": "Route fields returned from cache.",
            }
        )
        return cached_result

    def _save_cached(self, callsign: str, result: dict[str, Any]) -> None:
        if not result.get("matched"):
            return
        now = int(time.time())
        with self.lock:
            entries = {
                key: value for key, value in self._cache_entries().items()
                if isinstance(value, dict)
                and now - int(value.get("cached_utc", 0)) < self.CACHE_TTL_SECONDS
            }
            stored = dict(result)
            stored.update(
                {
                    "cache_hit": False,
                    "cache_age_seconds": 0,
                    "cache_ttl_seconds": self.CACHE_TTL_SECONDS,
                }
            )
            entries[callsign] = {"cached_utc": now, "result": stored}
            self._write_private_json(
                self.cache_path,
                {"entries": entries, "updated_utc": now},
            )

    def lookup_route(self, flight: str) -> dict[str, Any]:
        status = self.status()
        key = self._api_key()
        base = {
            "provider": "AirLabs",
            "diagnostic_only": True,
            "configured": status["configured"],
            "key_hint": status["key_hint"],
        }
        if not key:
            return {
                **base,
                "matched": False,
                "message": "No readable AirLabs key was found in runtime/settings/airlabs_api.json.",
            }
        callsign = self._clean_callsign(flight)
        if not callsign:
            return {
                **base,
                "matched": False,
                "message": "Provide a commercial flight ICAO callsign, for example UAL1234.",
            }
        cached = self._load_cached(callsign)
        if cached is not None:
            return cached

        query = urllib.parse.urlencode({"flight_icao": callsign, "api_key": key})
        request = urllib.request.Request(
            "https://airlabs.co/api/v9/flight?" + query,
            headers={"Accept": "application/json", "User-Agent": "RTL-Windows-ADS-B-Tracker/pi-port"},
        )
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")[:240]
            return {**base, "matched": False, "message": f"AirLabs HTTP {exc.code}: {body}"}
        except Exception as exc:
            return {**base, "matched": False, "message": f"AirLabs request failed: {exc}"}

        if isinstance(payload, dict) and payload.get("error"):
            error = payload["error"]
            message = error.get("message") if isinstance(error, dict) else str(error)
            return {**base, "matched": False, "message": f"AirLabs error: {message}"}

        record = payload.get("response") if isinstance(payload, dict) and isinstance(payload.get("response"), dict) else payload
        if not isinstance(record, dict):
            return {**base, "matched": False, "message": f"No route record returned for {callsign}."}

        fields = {
            "flight_icao": record.get("flight_icao") or callsign,
            "flight_iata": record.get("flight_iata"),
            "departure_iata": record.get("dep_iata"),
            "departure_icao": record.get("dep_icao"),
            "arrival_iata": record.get("arr_iata"),
            "arrival_icao": record.get("arr_icao"),
            "registration": record.get("reg_number"),
            "aircraft_icao": record.get("aircraft_icao"),
            "status": record.get("status"),
        }
        matched = any(
            fields[name]
            for name in ("departure_iata", "departure_icao", "arrival_iata", "arrival_icao")
        )
        result = {
            **base,
            "matched": matched,
            **fields,
            "cache_hit": False,
            "cache_age_seconds": 0,
            "cache_ttl_seconds": self.CACHE_TTL_SECONDS,
            "message": "Route fields returned." if matched else f"AirLabs returned no origin/destination for {callsign}.",
        }
        if matched:
            self._save_cached(callsign, result)
        return result


class PiPortHandler(BaseHTTPRequestHandler):
    server_version = "RTLWindowsPiPortBackend/0.1"

    @property
    def manager(self) -> DecoderManager:
        return self.server.manager  # type: ignore[attr-defined]

    @property
    def settings(self) -> PiPortSettingsStore:
        return self.server.settings  # type: ignore[attr-defined]

    @property
    def audio(self) -> AudioManager:
        return self.server.audio  # type: ignore[attr-defined]

    @property
    def audio_ops(self) -> AudioOperations:
        return self.server.audio_ops  # type: ignore[attr-defined]

    @property
    def catalog(self) -> AirbandCatalog:
        return self.server.catalog  # type: ignore[attr-defined]

    @property
    def scan(self) -> AirbandScanPort:
        return self.server.scan  # type: ignore[attr-defined]

    @property
    def trails(self) -> TrailHistoryCollector:
        return self.server.trails  # type: ignore[attr-defined]

    @property
    def airlabs(self) -> AirLabsIntegration:
        return self.server.airlabs  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        # Normal polling requests are intentionally silent at INFO level.
        # They remain available when the service is launched with --verbose.
        status = 0
        try:
            status = int(args[1]) if len(args) > 1 else 0
        except (TypeError, ValueError):
            status = 0
        if status >= 400:
            LOG.warning("%s - %s", self.address_string(), fmt % args)
        else:
            LOG.debug("%s - %s", self.address_string(), fmt % args)

    def send_json(self, payload: Any, code: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_binary(self, content: bytes, content_type: str, headers: dict[str, str] | None = None) -> None:
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(content)

    def send_file(self, path: Path) -> None:
        if not path.is_file():
            self.send_json({"error": "Not found."}, HTTPStatus.NOT_FOUND)
            return
        mime_type, _ = mimetypes.guess_type(str(path))
        self.send_binary(path.read_bytes(), mime_type or "application/octet-stream")

    def read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 16384:
            raise ValueError("A small JSON request body is required.")
        result = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(result, dict):
            raise ValueError("A JSON object is required.")
        return result

    @staticmethod
    def normalize_pi_aircraft_payload(payload: dict[str, Any]) -> dict[str, Any]:
        # Map Windows Dump1090 field names to readsb names consumed by the Pi UI.
        normalized = dict(payload)
        rows: list[dict[str, Any]] = []
        for native in payload.get("aircraft", []):
            aircraft = dict(native)
            if aircraft.get("alt_baro") is None and aircraft.get("altitude") is not None:
                aircraft["alt_baro"] = aircraft["altitude"]
            if aircraft.get("alt_geom") is None and aircraft.get("altitude") is not None:
                aircraft["alt_geom"] = aircraft["altitude"]
            if aircraft.get("gs") is None and aircraft.get("speed") is not None:
                aircraft["gs"] = aircraft["speed"]
            if aircraft.get("track") is None and aircraft.get("heading") is not None:
                aircraft["track"] = aircraft["heading"]
            if aircraft.get("seen_pos") is None and aircraft.get("seen") is not None:
                aircraft["seen_pos"] = aircraft["seen"]
            rows.append(aircraft)
        normalized["aircraft"] = rows
        return normalized

    def port_status(self) -> dict[str, Any]:
        aircraft_json: dict[str, Any] = {}
        if self.manager.is_running():
            try:
                aircraft_json = self.manager.query_aircraft()
            except Exception:
                aircraft_json = {}
        aircraft = aircraft_json.get("aircraft", [])
        positioned = sum(1 for item in aircraft if item.get("lat") is not None and item.get("lon") is not None)
        live_noaa = bool(self.audio_ops.noaa_live_active and self.audio.live_is_running())
        return {
            "service": "rtl-windows-pi-port-api",
            "readsb_json_available": self.manager.is_running(),
            "messages": int(aircraft_json.get("messages", 0)),
            "aircraft_count": len(aircraft),
            "aircraft_with_position": positioned,
            "audio_busy": bool(self.audio.live_is_running() or self.audio.is_running() or self.scan.status()["airband_scan_running"]),
            "audio_mode": "noaa_live" if live_noaa else "idle",
            "live_audio_running": live_noaa,
            "audio_receiver_serial": AUDIO_SERIAL,
            "noaa_station": self.settings.noaa_station,
            "noaa_frequency_hz": self.settings.noaa_frequency_hz,
            "configured_noaa_station": "Validated local NOAA channel",
            "configured_noaa_frequency_hz": int(NOAA_PROFILE["frequency_hz"]),
            "saved_noaa_selection_available": True,
            "saved_noaa_frequency_hz": self.settings.noaa_frequency_hz,
            "saved_noaa_station": self.settings.noaa_station,
            "rf_gain_db": NOAA_PROFILE["gain_db"],
            "audio_output_gain": None,
            "receiver_location_configured": True,
            "receiver_location": self.settings.pi_location(),
            **self.scan.status(),
        }

    def do_GET(self) -> None:
        try:
            request = urlparse(self.path)
            query = parse_qs(request.query)
            if request.path in ("/", "/index.html"):
                self.send_file(self.manager.root / "web" / "index.html")
            elif request.path == "/api/status" or request.path == "/api/readsb/status.json":
                self.send_json(self.port_status())
            elif request.path == "/api/aircraft.json":
                if not self.manager.is_running():
                    self.send_json({"error": "ADS-B decoder is not running."}, HTTPStatus.SERVICE_UNAVAILABLE)
                else:
                    self.send_json(self.normalize_pi_aircraft_payload(self.manager.query_aircraft()))
            elif request.path == "/api/settings/receiver":
                self.send_json({"configured": True, "receiver_location": self.settings.pi_location(), "default_airband_radius_miles": DEFAULT_RADIUS_MILES})
            elif request.path == "/api/airband/channels":
                self.send_json(self.scan.nearby())
            elif request.path == "/api/airband/scan/status":
                self.send_json({**self.port_status(), **self.scan.status()})
            elif request.path == "/api/airband/scan/last_audio.wav":
                if self.scan.last_audio is None:
                    self.send_json({"error": "No activity audio has been captured."}, HTTPStatus.NOT_FOUND)
                else:
                    self.send_binary(self.scan.last_audio, "audio/wav")
            elif request.path == "/api/airband/scan/best_audio.wav":
                if self.scan.best_audio is None:
                    self.send_json({"error": "No scan audio has been captured."}, HTTPStatus.NOT_FOUND)
                else:
                    self.send_binary(self.scan.best_audio, "audio/wav")
            elif request.path == "/api/airband/capture.wav":
                frequency_hz = int(query.get("frequency_hz", ["0"])[0])
                seconds = max(1, min(10, int(query.get("seconds", ["10"])[0])))
                channel = self.catalog.find_channel(frequency_hz)
                if channel is None:
                    self.send_json({"error": "Selected Airband frequency was not found in the FAA catalog."}, HTTPStatus.BAD_REQUEST)
                else:
                    self.send_binary(self.audio_ops.capture_airband(channel, seconds), "audio/wav")
            elif request.path == "/api/noaa/capture.wav":
                seconds = max(1, min(10, int(query.get("seconds", ["10"])[0])))
                self.send_binary(self.audio_ops.capture_noaa(self.settings, seconds), "audio/wav")
            elif request.path == "/api/noaa/live/audio.wav":
                after = int(query.get("from", ["0"])[0])
                next_chunk = self.audio.next_live_wav(after)
                if next_chunk is None:
                    self.send_response(HTTPStatus.NO_CONTENT)
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                else:
                    sequence, content = next_chunk
                    self.send_binary(content, "audio/wav", {"X-Source-Samples": str(max(1, sequence - after))})
            elif request.path == "/api/trails/history":
                self.send_json(self.trails.snapshot())
            elif request.path == "/api/diagnostics/airlabs/status":
                self.send_json(self.airlabs.status())
            elif request.path == "/api/diagnostics/airlabs/route":
                flight = query.get("flight", [""])[0]
                self.send_json(self.airlabs.lookup_route(flight))
            elif request.path == "/api/airband/test/status":
                self.send_json({"airband_test_running": False, "airband_test_state": "unavailable", "airband_test_message": "Simulated Airband diagnostic mode is not yet ported to Windows."})
            else:
                self.send_json({"error": "Endpoint not found."}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            LOG.exception("GET failed")
            self.send_json({"error": str(exc)}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def do_POST(self) -> None:
        try:
            request = urlparse(self.path)
            query = parse_qs(request.query)
            if request.path == "/api/settings/receiver":
                location = self.settings.save_pi_location(self.read_json())
                self.send_json({"saved": True, "receiver_location": location})
            elif request.path == "/api/settings/airband-radius":
                location = self.settings.save_airband_radius(self.read_json().get("airband_radius_miles"))
                self.send_json({"saved": True, "receiver_location": location, "noaa_selection_preserved": True})
            elif request.path == "/api/noaa/live/start":
                if self.scan.status()["airband_scan_running"]:
                    raise RuntimeError("Stop Airband background scan before starting NOAA listening.")
                self.audio_ops.live_noaa_start(self.settings)
                self.send_json({"started": True, **self.port_status()})
            elif request.path == "/api/noaa/live/stop":
                self.audio_ops.live_noaa_stop()
                self.send_json({"stopped": True, **self.port_status()})
            elif request.path in ("/api/noaa/auto/start", "/api/noaa/auto/rescan"):
                if self.scan.status()["airband_scan_running"]:
                    raise RuntimeError("Stop Airband background scan before selecting NOAA.")
                force = request.path.endswith("/rescan")
                if force or not self.settings.noaa_station.startswith("AUTO SELECT"):
                    survey = self.audio_ops.survey_noaa(self.settings)
                else:
                    survey = None
                self.audio_ops.live_noaa_start(self.settings)
                self.send_json({"started": True, "survey": survey, **self.port_status()})
            elif request.path == "/api/airband/scan/activity/start":
                if self.audio_ops.noaa_live_active:
                    raise RuntimeError("Stop NOAA Weather listening before starting Airband scanning.")
                scope = query.get("scope", ["priority"])[0]
                if scope not in ("priority", "all", "continuous"):
                    scope = "priority"
                self.send_json(self.scan.start(scope))
            elif request.path == "/api/airband/scan/activity/stop":
                self.send_json(self.scan.stop())
            elif request.path == "/api/trails/clear":
                self.send_json(self.trails.clear())
            elif request.path == "/api/diagnostics/airlabs/cache/clear":
                self.send_json(self.airlabs.clear_cache())
            elif request.path == "/api/diagnostics/airlabs/settings":
                payload = self.read_json()
                if bool(payload.get("clear")):
                    self.send_json(self.airlabs.save_key(""))
                else:
                    api_key = str(payload.get("api_key", "")).strip()
                    if len(api_key) < 8:
                        self.send_json({"error": "Enter a valid AirLabs API key before saving."}, HTTPStatus.BAD_REQUEST)
                    else:
                        self.send_json(self.airlabs.save_key(api_key))
            elif request.path.startswith("/api/airband/test/"):
                self.send_json({"error": "Simulated Airband diagnostic mode is not yet ported to Windows."}, HTTPStatus.NOT_IMPLEMENTED)
            else:
                self.send_json({"error": "Endpoint not found."}, HTTPStatus.NOT_FOUND)
        except Exception as exc:
            LOG.exception("POST failed")
            self.send_json({"error": str(exc)}, HTTPStatus.CONFLICT)


def main() -> int:
    parser = argparse.ArgumentParser(description="RTL-Windows-ADS-B-Tracker Raspberry Pi UI port backend")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--dump-http-port", type=int, default=18080)
    parser.add_argument("--settings-file")
    parser.add_argument("--airband-catalog-file")
    parser.add_argument("--autostart", action="store_true")
    parser.add_argument("--verbose", action="store_true", help="Enable DEBUG diagnostics including HTTP access requests.")
    parser.add_argument("--log-file", help="Diagnostic/error log file path. Defaults to runtime/logs/pi_port_backend.log.")
    parser.add_argument("--log-level", choices=("DEBUG", "INFO", "WARNING", "ERROR"), default="INFO")
    parser.add_argument("--log-max-bytes", type=int, default=2_000_000)
    parser.add_argument("--log-backup-count", type=int, default=3)
    parser.add_argument("--foreground-log", action="store_true", help="Also emit diagnostics to the terminal.")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    log_path = Path(args.log_file) if args.log_file else root / "runtime" / "logs" / "pi_port_backend.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    level_name = "DEBUG" if args.verbose else args.log_level
    logger = logging.getLogger()
    logger.handlers.clear()
    logger.setLevel(getattr(logging, level_name))
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
    file_handler = RotatingFileHandler(
        log_path,
        maxBytes=max(100_000, args.log_max_bytes),
        backupCount=max(1, args.log_backup_count),
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    if args.foreground_log:
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
    LOG.info("Diagnostic log file: %s; level=%s", log_path, level_name)
    settings_path = Path(args.settings_file) if args.settings_file else root / "runtime" / "settings" / "application_settings.json"
    settings = PiPortSettingsStore(settings_path)
    catalog_path = Path(args.airband_catalog_file) if args.airband_catalog_file else root / "runtime" / "settings" / "faa_airband_catalog.json"
    catalog = AirbandCatalog(catalog_path)
    airlabs = AirLabsIntegration(settings_path.parent)
    manager = DecoderManager(root, args.dump_http_port, settings)
    audio = AudioManager(manager, 10)
    audio_ops = AudioOperations(audio)
    scan = AirbandScanPort(audio_ops, settings, catalog)
    trails = TrailHistoryCollector(manager, root / "runtime" / "settings")
    server = ThreadingHTTPServer((args.host, args.port), PiPortHandler)
    server.manager = manager  # type: ignore[attr-defined]
    server.settings = settings  # type: ignore[attr-defined]
    server.catalog = catalog  # type: ignore[attr-defined]
    server.airlabs = airlabs  # type: ignore[attr-defined]
    server.audio = audio  # type: ignore[attr-defined]
    server.audio_ops = audio_ops  # type: ignore[attr-defined]
    server.scan = scan  # type: ignore[attr-defined]
    server.trails = trails  # type: ignore[attr-defined]

    def shutdown_handler(signum: int, frame: Any) -> None:
        del signum, frame
        scan.stop()
        audio_ops.live_noaa_stop()
        manager.stop()
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)
    try:
        if args.autostart:
            manager.start()
        trails.start()
        LOG.info("Pi UI Windows port listening at http://%s:%s", args.host, args.port)
        server.serve_forever()
    except KeyboardInterrupt:
        LOG.info("Backend shutdown requested")
    finally:
        trails.stop()
        scan.stop()
        audio_ops.live_noaa_stop()
        manager.stop()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
