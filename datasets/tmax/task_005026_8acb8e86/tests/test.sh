#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import signal
import subprocess
import time
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest
import requests

BASE_URL = "http://localhost:8080"
HEADERS = {"Authorization": "Bearer loc_token_99"}
INPUTS = [
    Path("/home/user/locales_old.json"),
    Path("/home/user/updates.csv"),
    Path("/home/user/vendor_translations.xml"),
    Path("/home/user/sequence.txt"),
    Path("/app/ui_walkthrough.mp4"),
]


def get(path, *, headers=HEADERS, params=None):
    try:
        return requests.get(f"{BASE_URL}{path}", headers=headers, params=params, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the server: {exc}")


def test_missing_auth():
    response = get("/locales", headers=None, params={"lang": "fr"})
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing Auth header, got {response.status_code}"


def test_invalid_auth():
    response = get("/locales", headers={"Authorization": "Bearer wrong_token"}, params={"lang": "fr"})
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid Auth header, got {response.status_code}"


def test_locales_fr():
    response = get("/locales", params={"lang": "fr"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    expected = {
        "ui_welcome": "Bienvenue",
        "ui_logout": "Se déconnecter",
        "ui_dashboard": "Tableau de bord",
        "ui_settings": "Paramètres",
    }
    for key, val in expected.items():
        assert data.get(key) == val, f"Expected key '{key}' to be '{val}', but got '{data.get(key)}'"


def test_locales_es():
    response = get("/locales", params={"lang": "es"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    expected = {"ui_welcome": "Bienvenido", "ui_logout": "Cerrar sesión"}
    for key, val in expected.items():
        assert data.get(key) == val, f"Expected key '{key}' to be '{val}', but got '{data.get(key)}'"


def test_subtitle_scene_1():
    response = get("/subtitle", params={"lang": "fr", "time": "2.0"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("key") == "ui_welcome", f"Expected key 'ui_welcome', got {data.get('key')}"
    assert data.get("text") == "Bienvenue", f"Expected text 'Bienvenue', got {data.get('text')}"


def test_subtitle_scene_3_fallback():
    response = get("/subtitle", params={"lang": "es", "time": "11.0"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("key") == "ui_settings", f"Expected key 'ui_settings', got {data.get('key')}"
    assert data.get("text") == "Settings", f"Expected text 'Settings', got {data.get('text')}"


def test_subtitle_scene_4_fallback():
    response = get("/subtitle", params={"lang": "de", "time": "15.0"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("key") == "ui_logout", f"Expected key 'ui_logout', got {data.get('key')}"
    assert data.get("text") == "Log out", f"Expected text 'Log out', got {data.get('text')}"


def listening_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    result = set()
    if not inodes:
        return result
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            pass
    return result


def process_launch_info(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    args = [part.decode(errors="surrogateescape") for part in raw if part]
    assert args, "The listening server has no restartable command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = dict(os.environ)
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        captured = {}
        for entry in entries:
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                captured[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
        if captured:
            env.update(captured)
    except OSError:
        pass
    return args, cwd, env


def stop_server_and_capture_command():
    pids = listening_pids()
    assert pids, "No process is listening on port 8080"
    info = process_launch_info(min(pids))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listening_pids():
        time.sleep(0.05)
    for pid in listening_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids():
        time.sleep(0.05)
    assert not listening_pids(), "Could not stop the original server for input-variation testing"
    return info


def write_varied_inputs(nonce):
    # Deliberately use decomposed Unicode and surrounding whitespace in every format.
    dec = "Cafe\u0301"
    baseline = {
        "ui_welcome": {"en": f"  Welcome-{nonce}  ", "fr": f" {dec}-welcome-{nonce} ", "es": "obsolete"},
        "ui_dashboard": {"en": f" Dashboard-{nonce} ", "de": "obsolete"},
        "ui_settings": {"en": f" Settings-{nonce} ", "de": f" Einstellung-{nonce} "},
        "ui_logout": {"en": f" Log-out-{nonce} ", "es": "obsolete"},
        f"ui_extra_{nonce}": {"en": f" Extra-{nonce} ", "fr": f" Extra-{dec}-{nonce} "},
    }
    Path("/home/user/locales_old.json").write_text(json.dumps(baseline, ensure_ascii=False), encoding="utf-8")

    with open("/home/user/updates.csv", "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["key", "lang", "text"])
        writer.writerow(["ui_welcome", "es", f"  CSV-{dec}-{nonce}  "])
        writer.writerow(["ui_logout", "fr", f" CSV-logout-{nonce} "])
        writer.writerow(["ui_logout", "es", f" CSV-salir-{nonce} "])
        writer.writerow(["ui_settings", "pt", f" CSV-config-{nonce} "])

    root = ET.Element("translations")
    xml_values = [
        ("ui_dashboard", "de", f"  XML-{dec}-{nonce}  "),
        ("ui_dashboard", "fr", f" XML-board-{nonce} "),
        ("ui_settings", "fr", f" XML-settings-{nonce} "),
        ("ui_welcome", "ja", f" XML-ja-{nonce} "),
    ]
    for key, lang, text in xml_values:
        item = ET.SubElement(root, "item", {"key": key, "lang": lang})
        item.text = text
    ET.ElementTree(root).write("/home/user/vendor_translations.xml", encoding="utf-8", xml_declaration=False)

    sequence = ["ui_welcome", "ui_dashboard", "ui_settings", "ui_logout"]
    shift = 1 + secrets.randbelow(3)
    sequence = sequence[shift:] + sequence[:shift]
    Path("/home/user/sequence.txt").write_text("\n".join(sequence) + "\n", encoding="utf-8")

    durations = [
        2.20 + secrets.randbelow(35) / 100,
        3.00 + secrets.randbelow(35) / 100,
        2.55 + secrets.randbelow(35) / 100,
        3.35 + secrets.randbelow(35) / 100,
    ]
    colors = ["magenta", "cyan", "black", "white"]
    command = ["ffmpeg", "-loglevel", "error", "-y"]
    for color, duration in zip(colors, durations):
        command += ["-f", "lavfi", "-i", f"color=c={color}:s=640x480:r=25:d={duration:.2f}"]
    command += [
        "-filter_complex", "[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[v]",
        "-map", "[v]", "/app/ui_walkthrough.mp4",
    ]
    subprocess.run(command, check=True, timeout=30)


def derive_merged_data():
    raw = json.loads(Path("/home/user/locales_old.json").read_text(encoding="utf-8"))
    merged = {
        key: {lang: unicodedata.normalize("NFC", str(text).strip()) for lang, text in translations.items()}
        for key, translations in raw.items()
    }
    with open("/home/user/updates.csv", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            merged.setdefault(row["key"], {})[row["lang"]] = unicodedata.normalize("NFC", row["text"].strip())
    root = ET.parse("/home/user/vendor_translations.xml").getroot()
    for item in root.findall("item"):
        merged.setdefault(item.attrib["key"], {})[item.attrib["lang"]] = unicodedata.normalize("NFC", (item.text or "").strip())
    return merged


def derive_scene_boundaries():
    result = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", "/app/ui_walkthrough.mp4", "-vf", "select='gt(scene,0.2)',showinfo", "-an", "-f", "null", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
        timeout=30,
    )
    changes = [float(value) for value in re.findall(r"showinfo[^\n]*pts_time:([0-9.]+)", result.stderr)]
    # ffmpeg's scene filter emits one selected frame for each hard cut.
    assert len(changes) == 3, f"Verifier could not derive exactly three hard cuts: {changes}"
    return [0.0] + changes


def restart_server(info):
    args, cwd, env = info
    proc = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + 12
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Server command exited during restart with status {proc.returncode}")
        try:
            response = requests.get(f"{BASE_URL}/locales", params={"lang": "en"}, headers=HEADERS, timeout=0.5)
            if response.status_code == 200:
                return proc
        except requests.RequestException:
            pass
        time.sleep(0.1)
    proc.terminate()
    pytest.fail("Restarted implementation did not listen on port 8080")


def test_dynamic_full_integration_and_video_analysis():
    launch_info = stop_server_and_capture_command()
    nonce = secrets.token_hex(6)
    write_varied_inputs(nonce)
    expected_by_key = derive_merged_data()
    boundaries = derive_scene_boundaries()
    sequence = [line.strip() for line in Path("/home/user/sequence.txt").read_text(encoding="utf-8").splitlines() if line.strip()]
    assert len(sequence) == 4 and len(boundaries) == 4
    restart_server(launch_info)

    # Authentication is required on both endpoint families.
    assert get("/subtitle", headers=None, params={"lang": "fr", "time": "0"}).status_code == 401
    assert get("/subtitle", headers={"Authorization": "Bearer bad"}, params={"lang": "fr", "time": "0"}).status_code == 401

    # Check every language and require the exact locale object, including an extra key.
    languages = sorted({lang for translations in expected_by_key.values() for lang in translations})
    for lang in languages + [f"missing_{nonce}"]:
        expected = {key: translations[lang] for key, translations in expected_by_key.items() if lang in translations}
        response = get("/locales", params={"lang": lang})
        assert response.status_code == 200
        assert response.json() == expected, f"Incorrect complete locale object for {lang}"
        for text in response.json().values():
            assert text == unicodedata.normalize("NFC", text), f"Non-NFC response for {lang}: {text!r}"

    # Exercise every dynamically ordered scene at multiple derived interior times,
    # including points on both sides of each detected hard cut.
    probe_languages = languages + [f"fallback_{nonce}"]
    duration_result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", "/app/ui_walkthrough.mp4"],
        capture_output=True, text=True, check=True, timeout=10,
    )
    video_end = float(duration_result.stdout.strip())
    ends = boundaries[1:] + [video_end]
    for index, (start, end) in enumerate(zip(boundaries, ends)):
        key = sequence[index]
        times = [start + (end - start) * 0.35, start + (end - start) * 0.70]
        if index > 0:
            times.append(start + min(0.20, (end - start) * 0.15))
        if index < 3:
            times.append(end - min(0.20, (end - start) * 0.15))
        for lang in probe_languages:
            expected_text = expected_by_key[key].get(lang, expected_by_key[key]["en"])
            for timestamp in times:
                response = get("/subtitle", params={"lang": lang, "time": f"{timestamp:.4f}"})
                assert response.status_code == 200
                assert response.json() == {"key": key, "text": expected_text}, (
                    f"Wrong subtitle for scene {index + 1}, language {lang}, time {timestamp}"
                )
                assert response.json()["text"] == unicodedata.normalize("NFC", response.json()["text"])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
