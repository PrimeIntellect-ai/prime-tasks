#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import glob
import importlib
import importlib.machinery
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

import pytest

URL = "http://localhost:8080/validate"


def raw_post(payload, timeout=4):
    data = json.dumps(payload, separators=(",", ":")).encode()
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to server at {URL}: {e.reason}. Is the Go server running?")


def post_after_quiet(payload):
    # Avoid interference from a preceding rate-limit test/window.
    time.sleep(1.15)
    return raw_post(payload)


def test_migrated_sources_and_extension():
    setup_path = "/app/legacy_tracker/setup.py"
    c_path = "/app/legacy_tracker/fastmath.c"
    assert os.path.isfile(setup_path)
    assert os.path.isfile(c_path)

    setup_text = open(setup_path, encoding="utf-8").read()
    c_text = open(c_path, encoding="utf-8").read()
    compile(setup_text, setup_path, "exec")
    assert "PyInit_fastmath" in c_text, "fastmath.c was not migrated to a Python 3 module initializer"
    assert "PyModule_Create" in c_text, "fastmath.c does not create a Python 3 module"
    assert "Py_InitModule" not in c_text, "deprecated Python 2 initialization remains"

    fastmath = importlib.import_module("fastmath")
    assert any(fastmath.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), "fastmath is not a compiled extension"
    for values in [(0, 0, 3, 4), (-2.5, 7.25, 11.0, -9.5), (1e3, -2e3, -4e3, 8e3)]:
        assert math.isclose(fastmath.dist(*values), math.hypot(values[2]-values[0], values[3]-values[1]), rel_tol=1e-12)


def test_extraction_artifact_and_rerun():
    stats_path = "/home/user/video_stats.json"
    assert os.path.isfile(stats_path), f"{stats_path} is missing"
    with open(stats_path) as f:
        data = json.load(f)
    assert data.get("frame_count") == 142
    assert data.get("status") == "success"
    assert math.isclose(data.get("test_dist"), 5.0)

    # Independently extract the supplied video, verify actual frame files, and execute the required script.
    with tempfile.TemporaryDirectory() as frame_dir:
        subprocess.run([
            "ffmpeg", "-v", "error", "-i", "/app/experiment.mp4",
            os.path.join(frame_dir, "frame_%06d.png")
        ], check=True, timeout=90)
        frames = glob.glob(os.path.join(frame_dir, "frame_*.png"))
        assert len(frames) == 142, f"ffmpeg extracted {len(frames)} frames, expected 142"
        before = os.stat(stats_path).st_mtime_ns
        time.sleep(0.01)
        subprocess.run([sys.executable, "/app/legacy_tracker/extract.py", frame_dir], check=True, timeout=30)
        assert os.stat(stats_path).st_mtime_ns > before, "extract.py did not regenerate video_stats.json"
        with open(stats_path) as f:
            regenerated = json.load(f)
        assert regenerated == {"frame_count": 142, "status": "success", "test_dist": 5.0}


def test_go_source_exists_and_builds():
    path = "/home/user/server.go"
    assert os.path.isfile(path), "required Go source /home/user/server.go is missing"
    text = open(path, encoding="utf-8").read()
    assert "package main" in text
    assert "go " in text or "chan " in text or "sync." in text, "server source shows no Go concurrency pattern"
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(["go", "build", "-o", os.path.join(d, "server"), path], check=True, timeout=60)


def test_generated_distance_cases_and_route():
    rng = random.Random(714239)
    cases = []
    # Random IDs and coordinates prevent corpus filename/ID/body substring classification.
    for i in range(8):
        x, y = rng.uniform(-500, 500), rng.uniform(-500, 500)
        angle = rng.uniform(0, 2 * math.pi)
        distance = [0.0, 1.0, 49.999, 50.0, 50.001, 63.7, 120.0, 37.25][i]
        p2 = {"x": x + distance * math.cos(angle), "y": y + distance * math.sin(angle)}
        payload = {"id": f"probe-{rng.getrandbits(64):016x}", "points": [{"x": x, "y": y}, p2]}
        cases.append((payload, 200 if distance <= 50.0 else 400))
    # Ensure every consecutive pair is considered, including a late anomaly.
    cases.append(({"id": "late-" + str(rng.getrandbits(64)), "points": [{"x": 1.2, "y": 3.4}, {"x": 31.2, "y": 43.4}, {"x": 31.2, "y": 93.401}]}, 400))

    for payload, expected in cases:
        status = post_after_quiet(payload)
        assert status == expected, f"distance-derived case expected {expected}, got {status}: {payload}"

    req = urllib.request.Request("http://localhost:8080/not-validate", data=b"{}", headers={"Content-Type": "application/json"}, method="POST")
    try:
        urllib.request.urlopen(req, timeout=2)
        pytest.fail("unexpected endpoint accepted")
    except urllib.error.HTTPError as e:
        assert e.code != 200


def test_adversarial_corpus():
    for directory, expected in [("/app/corpus/clean", 200), ("/app/corpus/evil", 400)]:
        files = glob.glob(os.path.join(directory, "*.json"))
        assert files
        for path in files:
            with open(path) as f:
                payload = json.load(f)
            assert post_after_quiet(payload) == expected


def test_exact_global_rate_limit():
    # After an idle interval, exactly ten simultaneous requests must be admitted and the rest rejected.
    time.sleep(1.25)
    token = f"burst-{random.SystemRandom().getrandbits(96):024x}"
    payloads = [{"id": f"{token}-{i}", "points": [{"x": i, "y": 0}, {"x": i + 1, "y": 1}]} for i in range(16)]
    barrier = __import__("threading").Barrier(len(payloads))

    def send(p):
        barrier.wait()
        return raw_post(p)

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(payloads)) as pool:
        statuses = list(pool.map(send, payloads))
    assert statuses.count(200) == 10, f"exactly 10 requests should be admitted in one second, got {statuses}"
    assert statuses.count(429) == 6, f"requests over the global limit must be 429, got {statuses}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
