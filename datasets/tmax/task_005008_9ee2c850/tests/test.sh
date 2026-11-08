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
import json
import socket
import subprocess

import pytest
import requests


def get_green_red_status():
    cmd = [
        "ffmpeg", "-i", "/app/deploy_logs.mp4",
        "-f", "image2pipe", "-pix_fmt", "rgb24",
        "-vcodec", "rawvideo", "-"
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    raw_video, _ = proc.communicate()
    assert proc.returncode == 0, "ffmpeg could not decode /app/deploy_logs.mp4"

    frame_size = 100 * 100 * 3
    assert len(raw_video) % frame_size == 0, "Decoded video contained partial frames"
    num_frames = len(raw_video) // frame_size
    assert num_frames == 30, f"Expected 30 video frames, found {num_frames}"

    statuses = []
    for i in range(num_frames):
        frame = raw_video[i * frame_size:(i + 1) * frame_size]
        green_sum = 0
        red_sum = 0
        for y in range(10):
            for x in range(10):
                idx = (y * 100 + x) * 3
                red_sum += frame[idx]
                green_sum += frame[idx + 1]
        statuses.append(green_sum > red_sum)
    return statuses


def parse_version(version):
    parts = tuple(map(int, version.split(".")))
    assert len(parts) == 3
    return parts


def matches_caret(base, version):
    target = parse_version(base)
    candidate = parse_version(version)
    if candidate < target:
        return False
    if target[0] != 0:
        return candidate[0] == target[0]
    if target[1] != 0:
        return candidate[0] == 0 and candidate[1] == target[1]
    return candidate[0] == 0 and candidate[1] == 0 and candidate[2] == target[2]


@pytest.fixture(scope="module")
def truth_data():
    statuses = get_green_red_status()
    with open("/home/user/versions.txt", "r", encoding="utf-8") as manifest:
        lines = manifest.read().splitlines()

    assert len(lines) == 30, f"Expected 30 manifest lines, found {len(lines)}"
    all_versions = []
    valid_versions = []
    for index, line in enumerate(lines):
        parts = line.strip().split()
        assert len(parts) == 2, f"Malformed manifest line {index + 1}: {line!r}"
        service, version = parts
        parse_version(version)
        all_versions.append((service, version))
        if statuses[index]:
            valid_versions.append((service, version))

    return {
        "green_count": sum(statuses),
        "valid_versions": valid_versions,
        "all_versions": all_versions,
    }


def expected_resolution(truth_data, service, target):
    versions = [
        version for candidate_service, version in truth_data["valid_versions"]
        if candidate_service == service
    ]
    if target.startswith("^"):
        base = target[1:]
        versions = [version for version in versions if matches_caret(base, version)]
    else:
        versions = [version for version in versions if version == target]
    return max(versions, key=parse_version) if versions else None


def assert_resolution(truth_data, service, target):
    expected = expected_resolution(truth_data, service, target)
    try:
        response = requests.get(
            "http://127.0.0.1:8080/deploy/resolve",
            params={"service": service, "target": target},
            timeout=2.0,
        )
    except requests.RequestException as exc:
        pytest.fail(f"HTTP GET failed for service={service!r}, target={target!r}: {exc}")

    if expected is None:
        assert response.status_code == 404, (
            f"Expected HTTP 404 for service={service!r}, target={target!r}; "
            f"got {response.status_code}: {response.text}"
        )
        return

    assert response.status_code == 200, (
        f"Expected HTTP 200 for service={service!r}, target={target!r}; "
        f"got {response.status_code}: {response.text}"
    )
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("service") == service, (
        f"Expected service {service!r}, got {data.get('service')!r}"
    )
    assert data.get("version") == expected, (
        f"Expected version {expected!r}, got {data.get('version')!r}"
    )


def test_tcp_status_monitor(truth_data):
    expected = f"GREEN_COUNT: {truth_data['green_count']}\n"
    for _ in range(3):
        try:
            with socket.create_connection(("127.0.0.1", 8081), timeout=2.0) as sock:
                sock.settimeout(2.0)
                sock.sendall(b"STATUS\n")
                chunks = []
                while True:
                    chunk = sock.recv(1024)
                    if not chunk:
                        break
                    chunks.append(chunk)
                data = b"".join(chunks).decode()
        except Exception as exc:
            pytest.fail(f"Failed to communicate with TCP server on port 8081: {exc}")
        assert data == expected, f"TCP server returned {data!r}, expected {expected!r}"


def test_http_api_all_exact_constraints(truth_data):
    # Every manifest version is checked. Successful entries must resolve exactly;
    # failed entries must not be exposed by the API.
    for service, version in truth_data["all_versions"]:
        assert_resolution(truth_data, service, version)


def test_http_api_caret_resolution_and_boundaries(truth_data):
    services = {service for service, _ in truth_data["all_versions"]}
    bases = {version for _, version in truth_data["all_versions"]}

    # Add derived, non-manifest lower bounds to exercise ordering and caret
    # boundaries rather than only replaying fixture strings.
    for _, version in truth_data["valid_versions"]:
        major, minor, patch = parse_version(version)
        bases.add(f"{major}.{minor}.{patch + 1}")
        bases.add(f"{major}.{minor + 1}.0")
        bases.add(f"{major + 1}.0.0")

    for service in sorted(services):
        for base in sorted(bases, key=parse_version):
            assert_resolution(truth_data, service, f"^{base}")


def test_http_api_unknown_service_and_fixed_not_found(truth_data):
    assert_resolution(truth_data, "service-not-in-manifest", "1.0.0")
    assert_resolution(truth_data, "service-not-in-manifest", "^0.1.0")
    # Preserve the original verifier's explicit high-version 404 assertion.
    assert_resolution(truth_data, "auth-service", "^99.99.99")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
