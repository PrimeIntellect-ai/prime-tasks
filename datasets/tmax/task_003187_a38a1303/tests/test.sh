#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import socket
import subprocess
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

import pytest

BASE_URL = "http://127.0.0.1:9090"
PROJECT_ROOTS = [Path(p) for p in ("/app", "/home", "/root", "/workspace") if Path(p).exists()]


def read_metadata_with_ocr():
    outputs = []
    for psm in (6, 3, 11):
        proc = subprocess.run(
            ["tesseract", "/app/legacy_metadata.png", "stdout", "--psm", str(psm)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        if proc.returncode == 0:
            outputs.append(proc.stdout)
    text = "\n".join(outputs)

    threshold_match = re.search(
        r"CRITICAL[\s_-]*ANOMALY[\s_-]*THRESHOLD\s*[=:]?\s*(\d+)",
        text,
        re.IGNORECASE,
    )
    target_match = re.search(
        r"TARGET[\s_-]*SENSOR\s*[=:]?\s*([A-Z][A-Z0-9_-]*)",
        text,
        re.IGNORECASE,
    )
    assert threshold_match, f"OCR did not recover CRITICAL_ANOMALY_THRESHOLD. OCR output: {text!r}"
    assert target_match, f"OCR did not recover TARGET_SENSOR. OCR output: {text!r}"

    target = target_match.group(1).upper().rstrip("_-.")
    # Tesseract can confuse the zero in a sensor identifier with the letter O.
    if re.fullmatch(r"SO\d+", target):
        target = "S0" + target[2:]
    return int(threshold_match.group(1)), target


def compute_ground_truth():
    threshold, target_sensor = read_metadata_with_ocr()
    rows = defaultdict(list)
    with open("/app/sensor_data.csv", newline="") as f:
        for row in csv.DictReader(f):
            rows[row["sensor_id"]].append((row["timestamp"], float(row["value"])))

    assert rows, "sensor_data.csv contained no sensor readings"
    assert target_sensor in rows, f"OCR target {target_sensor!r} is not present in sensor_data.csv"

    data = {
        sensor: [value for _, value in sorted(samples, key=lambda item: item[0])]
        for sensor, samples in rows.items()
    }

    stats = {}
    for sensor, values in data.items():
        mean = sum(values) / len(values)
        variance = sum((value - mean) ** 2 for value in values) / len(values)
        stddev = math.sqrt(variance)
        anomalies = sum(
            value > mean + 3 * stddev or value < mean - 3 * stddev
            for value in values
        )
        stats[sensor] = {
            "min": round(min(values), 2),
            "max": round(max(values), 2),
            "mean": round(mean, 2),
            "anomalies": anomalies,
            "flagged": anomalies > threshold,
        }

    target_values = data[target_sensor]
    distances = {}
    for sensor, values in data.items():
        if sensor == target_sensor:
            continue
        assert len(values) == len(target_values), "Sensor series lengths differ"
        distances[sensor] = math.sqrt(
            sum((left - right) ** 2 for left, right in zip(target_values, values))
        )
    most_similar = min(distances, key=distances.get)
    return stats, target_sensor, most_similar, round(distances[most_similar], 2)


def get_json(path):
    try:
        with urllib.request.urlopen(BASE_URL + path, timeout=5) as response:
            assert response.status == 200
            content_type = response.headers.get_content_type()
            assert content_type == "application/json", f"Expected JSON Content-Type, got {content_type}"
            return json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        pytest.fail(f"Request to {path} failed: {exc}")


def assert_rounded_number(value, expected, name):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be numeric"
    assert math.isfinite(float(value)), f"{name} must be finite"
    assert math.isclose(float(value), expected, abs_tol=0.011), f"Expected {name}={expected}, got {value}"
    assert math.isclose(float(value) * 100, round(float(value) * 100), abs_tol=1e-7), f"{name} is not rounded to 2 decimals"


def iter_project_files():
    allowed_suffixes = {".cpp", ".cc", ".cxx", ".h", ".hpp", ".py", ".sh", ".mk", ".txt"}
    for root in PROJECT_ROOTS:
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "__pycache__"}]
            for name in files:
                path = Path(current) / name
                if path.suffix.lower() not in allowed_suffixes and name.lower() not in {"makefile", "cmakelists.txt", ".bash_history"}:
                    continue
                try:
                    if path.is_file() and path.stat().st_size <= 2_000_000:
                        yield path
                except OSError:
                    pass


def listener_pids():
    inodes = set()
    for netfile in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(netfile).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            if int(local.rsplit(":", 1)[1], 16) == 9090 and state == "0A":
                inodes.add(inode)
    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
        except (OSError, PermissionError):
            pass
    return pids


@pytest.fixture(scope="module")
def ground_truth():
    return compute_ground_truth()


def test_required_implementation_artifacts_and_running_server():
    files = list(iter_project_files())
    cpp_files = [p for p in files if p.suffix.lower() in {".cpp", ".cc", ".cxx"}]
    assert cpp_files, "No C++ data-processing source file was found"

    texts = {}
    for path in files:
        try:
            texts[path] = path.read_text(errors="ignore")
        except OSError:
            pass
    combined = "\n".join(texts.values())
    cpp_text = "\n".join(texts.get(path, "") for path in cpp_files)

    assert re.search(r"sensor_data\.csv|timestamp.*sensor_id.*value", cpp_text, re.IGNORECASE | re.DOTALL), \
        "The C++ source does not appear to process the sensor CSV"
    assert re.search(
        r"std\s*::\s*(thread|jthread|async)|std\s*::\s*execution\s*::\s*par|#\s*pragma\s+omp|pthread_create",
        cpp_text,
        re.IGNORECASE,
    ), "No C++ parallel-processing implementation was found"
    assert re.search(r"tesseract|pytesseract|ocr", combined, re.IGNORECASE), \
        "No OCR invocation or OCR integration was found in the submitted implementation"

    compilable = False
    errors = []
    for source in cpp_files:
        try:
            proc = subprocess.run(
                ["g++", "-std=c++17", "-pthread", "-fsyntax-only", "-I", str(source.parent), str(source)],
                cwd=str(source.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            if proc.returncode == 0:
                compilable = True
                break
            errors.append(f"{source}: {proc.stderr[-500:]}")
        except subprocess.TimeoutExpired:
            errors.append(f"{source}: compilation timed out")
    assert compilable, "No submitted C++ pipeline source compiles as C++17:\n" + "\n".join(errors)

    pids = listener_pids()
    assert pids, "No running process is listening on port 9090"
    assert any(
        "127.0.0.1:9090" in line
        for line in subprocess.run(["ss", "-ltn"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.splitlines()
    ) if Path("/usr/bin/ss").exists() else True


def test_stats_s02_preserves_original_assertions(ground_truth):
    stats, _, _, _ = ground_truth
    expected = stats["S02"]
    data = get_json("/stats?sensor_id=S02")
    assert data.get("anomalies") == expected["anomalies"]
    assert data.get("flagged") is True
    assert math.isclose(data.get("mean"), expected["mean"], abs_tol=0.02)


def test_stats_s01_preserves_original_assertion(ground_truth):
    stats, _, _, _ = ground_truth
    data = get_json("/stats?sensor_id=S01")
    assert data.get("flagged") is False


def test_complete_stats_for_every_sensor(ground_truth):
    stats, _, _, _ = ground_truth
    for sensor, expected in stats.items():
        data = get_json("/stats?" + urllib.parse.urlencode({"sensor_id": sensor}))
        assert isinstance(data, dict), f"Stats response for {sensor} must be a JSON object"
        for key in ("min", "max", "mean", "anomalies", "flagged"):
            assert key in data, f"Stats response for {sensor} is missing {key}"
        assert_rounded_number(data["min"], expected["min"], f"{sensor}.min")
        assert_rounded_number(data["max"], expected["max"], f"{sensor}.max")
        assert_rounded_number(data["mean"], expected["mean"], f"{sensor}.mean")
        assert type(data["anomalies"]) is int, f"{sensor}.anomalies must be an integer"
        assert data["anomalies"] == expected["anomalies"], f"Incorrect anomaly count for {sensor}"
        assert type(data["flagged"]) is bool, f"{sensor}.flagged must be boolean"
        assert data["flagged"] is expected["flagged"], f"Incorrect flagged status for {sensor}"


def test_similar_preserves_and_expands_original_assertions(ground_truth):
    _, target, most_similar, distance = ground_truth
    data = get_json("/similar")
    assert data.get("target") == target
    assert data.get("most_similar") == most_similar
    assert math.isclose(data.get("distance"), distance, abs_tol=0.02)
    assert_rounded_number(data.get("distance"), distance, "distance")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
