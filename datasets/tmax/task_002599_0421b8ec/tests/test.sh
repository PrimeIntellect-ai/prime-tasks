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
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/api/analyze"
TOKEN = "XY88-SPEC-9Z"
CSV_PATH = Path("/app/raw_spectrum.csv")


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])
    if not inodes:
        return
    for proc_dir in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc_dir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(proc_dir.name), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (OSError, PermissionError):
            pass
    time.sleep(0.5)


def find_and_build_rust_binary():
    manifests = []
    for root in (Path("/home/user"), Path("/app")):
        if not root.exists():
            continue
        for manifest in root.rglob("Cargo.toml"):
            text = str(manifest)
            if "/target/" in text or "/.cargo/registry/" in text:
                continue
            manifests.append(manifest)
    assert manifests, "No Rust Cargo project was created"
    manifests.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    errors = []
    for manifest in manifests:
        cwd = manifest.parent
        try:
            meta_run = subprocess.run(
                ["cargo", "metadata", "--format-version", "1", "--no-deps"],
                cwd=cwd, text=True, capture_output=True, timeout=30
            )
            if meta_run.returncode != 0:
                errors.append(f"{manifest}: metadata failed")
                continue
            metadata = json.loads(meta_run.stdout)
            bins = []
            for package in metadata.get("packages", []):
                for target in package.get("targets", []):
                    if "bin" in target.get("kind", []):
                        bins.append(target["name"])
            if not bins:
                errors.append(f"{manifest}: no binary target")
                continue

            rust_sources = [p for p in cwd.rglob("*.rs") if "/target/" not in str(p)]
            assert rust_sources, f"No Rust source files found in {cwd}"
            source_text = "\n".join(p.read_text(errors="ignore") for p in rust_sources)
            assert "1000" in source_text, "Rust source does not specify the required 1000 bootstrap iterations"

            for bin_name in bins:
                built = subprocess.run(
                    ["cargo", "build", "--release", "--bin", bin_name],
                    cwd=cwd, text=True, capture_output=True, timeout=240
                )
                if built.returncode != 0:
                    errors.append(f"{manifest} ({bin_name}): build failed: {built.stderr[-1000:]}")
                    continue
                binary = Path(metadata["target_directory"]) / "release" / bin_name
                if binary.is_file() and binary.read_bytes()[:4] == b"\x7fELF":
                    return binary, cwd
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{manifest}: {exc}")
    pytest.fail("Could not build a Rust server artifact: " + " | ".join(errors))


class ServerController:
    def __init__(self, binary, cwd):
        self.binary = binary
        self.cwd = cwd
        self.proc = None

    def stop(self):
        if self.proc is not None and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
                self.proc.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        self.proc = None
        kill_port_8080()

    def start(self):
        self.stop()
        self.proc = subprocess.Popen(
            [str(self.binary)], cwd=self.cwd,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        deadline = time.time() + 15
        while time.time() < deadline:
            if self.proc.poll() is not None:
                pytest.fail(f"Built Rust server exited with status {self.proc.returncode}")
            try:
                response = requests.get(URL, timeout=0.5)
                if response.status_code in (200, 401):
                    return
            except requests.RequestException:
                pass
            time.sleep(0.15)
        pytest.fail("Built Rust server did not listen on 127.0.0.1:8080")


@pytest.fixture(scope="session")
def service():
    original = CSV_PATH.read_bytes()
    kill_port_8080()
    binary, cwd = find_and_build_rust_binary()
    controller = ServerController(binary, cwd)
    controller.start()
    yield controller
    controller.stop()
    CSV_PATH.write_bytes(original)
    # Leave the verified Rust server running against the original input.
    controller.start()


def read_rows():
    with CSV_PATH.open(newline="") as f:
        reader = csv.DictReader(f)
        return [(float(row["x"]), float(row["y"])) for row in reader]


def smoothed_peak(rows):
    ys = [y for _, y in rows]
    smooth = []
    for i in range(len(ys)):
        lo = max(0, i - 2)
        hi = min(len(ys), i + 3)
        smooth.append(sum(ys[lo:hi]) / (hi - lo))
    index = max(range(len(rows)), key=lambda i: smooth[i])
    return rows[index][0]


def percentile(values, pct):
    values = sorted(values)
    pos = (len(values) - 1) * pct
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return values[lo]
    return values[lo] * (hi - pos) + values[hi] * (pos - lo)


def reference_bootstrap(rows, iterations=20000):
    rng = random.Random(secrets.randbits(128))
    n = len(rows)
    peaks = []
    for _ in range(iterations):
        sample = [rows[rng.randrange(n)] for _ in range(n)]
        sample.sort(key=lambda pair: pair[0])
        peaks.append(smoothed_peak(sample))
    return percentile(peaks, 0.025), percentile(peaks, 0.975)


def assert_payload(response):
    assert response.status_code == 200, (
        f"Expected HTTP 200 for correct token, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    for key in ["peak_x", "ci_95_low", "ci_95_high"]:
        assert key in data, f"Missing key '{key}' in JSON response: {data}"
        assert isinstance(data[key], (int, float)), f"Key '{key}' must be a number, got {type(data[key])}"
        assert math.isfinite(float(data[key])), f"Key '{key}' must be finite"
    return {key: float(data[key]) for key in ("peak_x", "ci_95_low", "ci_95_high")}


def authorized_request(timeout=30):
    try:
        return requests.get(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server or request timed out: {exc}")


def test_unauthorized_wrong_token(service):
    headers = {"Authorization": "Bearer WRONG_TOKEN"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server or request timed out: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 for wrong token, got {response.status_code}"


def test_unauthorized_missing_token(service):
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server or request timed out: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 for missing token, got {response.status_code}"


def test_authorized_and_response_validation(service):
    data = assert_payload(authorized_request())
    peak_x = data["peak_x"]
    ci_95_low = data["ci_95_low"]
    ci_95_high = data["ci_95_high"]

    # Preserve the original assertions.
    assert 48.0 <= peak_x <= 52.0, f"peak_x {peak_x} is out of expected bounds [48.0, 52.0]"
    assert ci_95_low <= peak_x, f"ci_95_low {ci_95_low} should be <= peak_x {peak_x}"
    assert ci_95_high >= peak_x, f"ci_95_high {ci_95_high} should be >= peak_x {peak_x}"

    # Recompute both the smoothing result and the bootstrap distribution from the CSV.
    rows = read_rows()
    expected_peak = smoothed_peak(rows)
    assert abs(peak_x - expected_peak) < 1e-5, (
        f"peak_x {peak_x} does not match the recomputed moving-average peak {expected_peak}"
    )
    ref_low, ref_high = reference_bootstrap(rows)
    gaps = [rows[i + 1][0] - rows[i][0] for i in range(len(rows) - 1)]
    tolerance = max(gaps) * 4.0
    assert abs(ci_95_low - ref_low) <= tolerance, (
        f"ci_95_low {ci_95_low} is inconsistent with bootstrap reference {ref_low}"
    )
    assert abs(ci_95_high - ref_high) <= tolerance, (
        f"ci_95_high {ci_95_high} is inconsistent with bootstrap reference {ref_high}"
    )


def write_probe(rows):
    with CSV_PATH.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["x", "y"])
        writer.writerows((f"{x:.6f}", f"{y:.6f}") for x, y in rows)


def test_rust_server_recomputes_unseen_inputs(service):
    # This probe has a raw spike at index 5, but the five-point moving-average
    # maximum is at the center of a separate five-row plateau.
    offset = 120.0 + secrets.randbelow(50000) / 1000.0
    rows = []
    for i in range(35):
        y = 0.0
        if i == 5:
            y = 20.0
        if 20 <= i <= 24:
            y = 6.0
        rows.append((offset + i * 0.73, y))
    write_probe(rows)
    service.start()

    data = assert_payload(authorized_request())
    expected_peak = smoothed_peak(rows)
    assert abs(data["peak_x"] - expected_peak) < 1e-5, (
        f"Server did not recompute the five-point moving-average peak: "
        f"got {data['peak_x']}, expected {expected_peak}"
    )

    ref_low, ref_high = reference_bootstrap(rows, iterations=25000)
    tolerance = 3.5 * 0.73
    assert min(x for x, _ in rows) <= data["ci_95_low"] <= max(x for x, _ in rows)
    assert min(x for x, _ in rows) <= data["ci_95_high"] <= max(x for x, _ in rows)
    assert data["ci_95_low"] <= data["ci_95_high"]
    assert abs(data["ci_95_low"] - ref_low) <= tolerance, (
        f"Probe ci_95_low {data['ci_95_low']} is inconsistent with bootstrap reference {ref_low}"
    )
    assert abs(data["ci_95_high"] - ref_high) <= tolerance, (
        f"Probe ci_95_high {data['ci_95_high']} is inconsistent with bootstrap reference {ref_high}"
    )

    # A second probe distinguishes the required truncated edge-window average
    # from implementations that always divide by five.
    edge_offset = 230.0 + secrets.randbelow(50000) / 1000.0
    edge_rows = []
    for i in range(30):
        y = 9.0 if i in (0, 1) else (5.0 if 15 <= i <= 19 else 0.0)
        edge_rows.append((edge_offset + i * 0.61, y))
    write_probe(edge_rows)
    service.start()
    edge_data = assert_payload(authorized_request())
    edge_expected = smoothed_peak(edge_rows)
    assert abs(edge_data["peak_x"] - edge_expected) < 1e-5, (
        f"Boundary moving-average handling is incorrect: got {edge_data['peak_x']}, expected {edge_expected}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
