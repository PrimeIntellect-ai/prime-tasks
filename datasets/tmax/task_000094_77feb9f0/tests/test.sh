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
import datetime
import json
import secrets
import subprocess

import pytest
import requests
from zoneinfo import ZoneInfo

API_URL = "http://127.0.0.1:8080/time"

FRENCH_DAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
FRENCH_MONTHS = [
    "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre",
]


def run(command, timeout=15):
    return subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=True).stdout


def derive_configuration():
    dimensions = run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
        "/app/server_ops.mp4",
    ]).strip()
    width, height = map(int, dimensions.split("x"))
    raw = subprocess.run([
        "ffmpeg", "-v", "error", "-i", "/app/server_ops.mp4",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
    ], capture_output=True, timeout=30, check=True).stdout

    frame_size = width * height * 3
    assert frame_size > 0 and len(raw) % frame_size == 0, "Could not decode complete video frames"
    red_frames = 0
    pixels = width * height
    for offset in range(0, len(raw), frame_size):
        frame = raw[offset:offset + frame_size]
        mean_r = sum(frame[0::3]) / pixels
        mean_g = sum(frame[1::3]) / pixels
        mean_b = sum(frame[2::3]) / pixels
        if mean_r >= 240 and mean_g <= 20 and mean_b <= 20:
            red_frames += 1

    with open("/app/config_options.txt", encoding="utf-8") as config_file:
        lines = [line.strip() for line in config_file if line.strip()]
    assert 1 <= red_frames <= len(lines), f"Red-frame count {red_frames} has no configuration line"
    parts = [part.strip() for part in lines[red_frames - 1].split(",")]
    assert len(parts) == 3, "Selected configuration line is malformed"
    return tuple(parts)


TIMEZONE, LOCALE, API_KEY = derive_configuration()


def expected_strings(before, after):
    zone = ZoneInfo(TIMEZONE)
    first = int(before.timestamp()) - 3
    last = int(after.timestamp()) + 3
    values = set()
    for timestamp in range(first, last + 1):
        value = datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).astimezone(zone)
        values.add(
            f"{FRENCH_DAYS[value.weekday()]}, {value.day:02d} "
            f"{FRENCH_MONTHS[value.month - 1]} {value.year:04d} "
            f"{value.hour:02d}:{value.minute:02d}:{value.second:02d} {value.tzname()}"
        )
    return values


def assert_time_document(data, before, after):
    assert type(data) is dict, "Response JSON must be an object"
    assert set(data) == {"current_time"}, "JSON response must contain only the 'current_time' key"
    current_time = data["current_time"]
    assert isinstance(current_time, str), "current_time must be a string"

    lower_time = current_time.lower()
    assert any(day in lower_time for day in FRENCH_DAYS), f"Expected French day, got: {current_time}"
    assert any(month in lower_time for month in FRENCH_MONTHS), f"Expected French month, got: {current_time}"
    assert "CET" in current_time or "CEST" in current_time, f"Expected CET/CEST, got: {current_time}"

    assert current_time in expected_strings(before, after), (
        "current_time is not the current time in the required timezone, locale, and exact "
        f"%A, %d %B %Y %H:%M:%S %Z format: {current_time}"
    )


def compose_container_id(service):
    value = run(["docker", "compose", "-f", "/app/docker-compose.yml", "ps", "-q", service]).strip()
    assert value, f"Compose service {service} has no container"
    return value.splitlines()[0]


def test_compose_network_and_host_binding():
    config = json.loads(run([
        "docker", "compose", "-f", "/app/docker-compose.yml", "config", "--format", "json"
    ]))
    services = config.get("services", {})
    assert "proxy" in services and "time_service" in services, "Required Compose services are missing"

    def network_names(service):
        networks = service.get("networks", {})
        return set(networks if isinstance(networks, list) else networks.keys())

    shared = network_names(services["proxy"]) & network_names(services["time_service"])
    assert shared, "proxy and time_service do not share a Compose network"

    ports = services["proxy"].get("ports", [])
    matching_ports = [
        port for port in ports if str(port.get("target")) == "80" and str(port.get("published")) == "8080"
    ]
    assert matching_ports, "proxy does not publish container port 80 as host port 8080"
    assert all(port.get("host_ip") == "127.0.0.1" for port in matching_ports), (
        "proxy port 8080 must be bound specifically to 127.0.0.1"
    )

    proxy_id = compose_container_id("proxy")
    time_id = compose_container_id("time_service")
    proxy_info = json.loads(run(["docker", "inspect", proxy_id]))[0]
    time_info = json.loads(run(["docker", "inspect", time_id]))[0]
    assert proxy_info["State"]["Running"], "proxy container is not running"
    assert time_info["State"]["Running"], "time_service container is not running"
    runtime_shared = set(proxy_info["NetworkSettings"]["Networks"]) & set(time_info["NetworkSettings"]["Networks"])
    assert runtime_shared, "Running containers do not share a Docker network"

    bindings = proxy_info["NetworkSettings"]["Ports"].get("80/tcp") or []
    assert bindings, "proxy container port 80 has no runtime host binding"
    assert all(binding["HostIp"] == "127.0.0.1" and binding["HostPort"] == "8080" for binding in bindings), (
        "Runtime proxy binding is not exclusively 127.0.0.1:8080"
    )

    before = datetime.datetime.now(datetime.timezone.utc)
    body = run([
        "docker", "exec", proxy_id, "wget", "-qO-",
        "--header", f"X-API-Key: {API_KEY}",
        "http://time_service:5000/time",
    ])
    after = datetime.datetime.now(datetime.timezone.utc)
    assert_time_document(json.loads(body), before, after)


def test_missing_api_key():
    try:
        response = requests.get(API_URL, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to proxy at {API_URL}: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 for missing API key, got {response.status_code}"


def test_invalid_api_key():
    invalid_key = secrets.token_urlsafe(24)
    assert invalid_key != API_KEY
    try:
        response = requests.get(API_URL, headers={"X-API-Key": invalid_key}, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to proxy at {API_URL}: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 for invalid API key, got {response.status_code}"


def test_valid_api_key_and_response_format():
    before = datetime.datetime.now(datetime.timezone.utc)
    try:
        response = requests.get(API_URL, headers={"X-API-Key": API_KEY}, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to proxy at {API_URL}: {exc}")
    after = datetime.datetime.now(datetime.timezone.utc)

    assert response.status_code == 200, f"Expected HTTP 200 for valid API key, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert_time_document(data, before, after)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
