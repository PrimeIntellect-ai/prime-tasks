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
rm -rf /tmp/verifier_reference_frames
mkdir -p /tmp/verifier_reference_frames
status=0

ffmpeg -hide_banner -loglevel error -i /app/factory_feed.mp4 -vf fps=1 -vsync 0 /tmp/verifier_reference_frames/frame_%04d.png || status=1

cat > /tmp/image_probe.go <<'GO_EOF'
package main

import (
    "encoding/json"
    "fmt"
    "image"
    _ "image/jpeg"
    _ "image/png"
    "os"
)

type Result struct {
    Width  int        `json:"width"`
    Height int        `json:"height"`
    Average float64   `json:"average"`
    Histogram [8]float64 `json:"histogram"`
    MAE *float64      `json:"mae,omitempty"`
}

func load(path string) image.Image {
    f, err := os.Open(path)
    if err != nil {
        panic(err)
    }
    defer f.Close()
    img, _, err := image.Decode(f)
    if err != nil {
        panic(err)
    }
    return img
}

func grayAt(img image.Image, x, y int) uint8 {
    r, g, b, _ := img.At(x, y).RGBA()
    // This is the conversion used by Go's color.GrayModel.
    yy := (19595*r + 38470*g + 7471*b + 1<<15) >> 24
    return uint8(yy)
}

func main() {
    if len(os.Args) < 2 || len(os.Args) > 3 {
        fmt.Fprintln(os.Stderr, "usage: image_probe IMAGE [REFERENCE]")
        os.Exit(2)
    }
    img := load(os.Args[1])
    bounds := img.Bounds()
    n := bounds.Dx() * bounds.Dy()
    if n == 0 {
        panic("empty image")
    }

    var counts [8]uint64
    var total uint64
    for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
        for x := bounds.Min.X; x < bounds.Max.X; x++ {
            v := grayAt(img, x, y)
            total += uint64(v)
            counts[int(v)/32]++
        }
    }

    out := Result{Width: bounds.Dx(), Height: bounds.Dy(), Average: float64(total) / float64(n)}
    for i := range counts {
        out.Histogram[i] = float64(counts[i]) / float64(n)
    }

    if len(os.Args) == 3 {
        ref := load(os.Args[2])
        rb := ref.Bounds()
        if rb.Dx() != bounds.Dx() || rb.Dy() != bounds.Dy() {
            panic("image dimensions differ")
        }
        var diff uint64
        for y := 0; y < bounds.Dy(); y++ {
            for x := 0; x < bounds.Dx(); x++ {
                a := int(grayAt(img, bounds.Min.X+x, bounds.Min.Y+y))
                b := int(grayAt(ref, rb.Min.X+x, rb.Min.Y+y))
                if a > b {
                    diff += uint64(a-b)
                } else {
                    diff += uint64(b-a)
                }
            }
        }
        mae := float64(diff) / float64(n)
        out.MAE = &mae
    }

    if err := json.NewEncoder(os.Stdout).Encode(out); err != nil {
        panic(err)
    }
}
GO_EOF

go build -o /tmp/image_probe /tmp/image_probe.go || status=1

cat > /tmp/test_final_state.py <<'PY_EOF'
import json
import math
import os
import sqlite3
import subprocess

import pytest
import requests

FRAMES_DIR = "/home/user/frames"
CORRUPTED_LOG = "/home/user/corrupted_frames.log"
DB_PATH = "/home/user/features.db"
SERVICE_URL = "http://127.0.0.1:8080/search"
REFERENCE_DIR = "/tmp/verifier_reference_frames"
EXPECTED_MISSING = {
    "frame_0012.jpg", "frame_0013.jpg", "frame_0014.jpg", "frame_0045.jpg"
}
EXPECTED_VALID = {
    f"frame_{i:04d}.jpg" for i in range(1, 61)
} - EXPECTED_MISSING

_probe_cache = {}

def probe(path, reference=None):
    key = (path, reference)
    if key not in _probe_cache:
        command = ["/tmp/image_probe", path]
        if reference is not None:
            command.append(reference)
        completed = subprocess.run(command, capture_output=True, text=True, timeout=10)
        assert completed.returncode == 0, (
            f"Could not decode/probe {path}: {completed.stderr}"
        )
        _probe_cache[key] = json.loads(completed.stdout)
    return _probe_cache[key]


def reference_path(filename):
    return os.path.join(REFERENCE_DIR, filename.replace(".jpg", ".png"))


def test_frames_extracted_and_cleaned():
    assert os.path.isdir(FRAMES_DIR), f"Directory {FRAMES_DIR} does not exist."

    reference_files = {
        name for name in os.listdir(REFERENCE_DIR)
        if name.startswith("frame_") and name.endswith(".png")
    }
    assert len(reference_files) == 60, f"Expected 60 source frames, found {len(reference_files)}."

    # Independently derive the corrupt set from the supplied video.
    derived_corrupt = set()
    for i in range(1, 61):
        jpg_name = f"frame_{i:04d}.jpg"
        ref = probe(reference_path(jpg_name))
        assert ref["width"] == 640 and ref["height"] == 480
        if ref["average"] < 5.0:
            derived_corrupt.add(jpg_name)
    assert derived_corrupt == EXPECTED_MISSING

    files = set(os.listdir(FRAMES_DIR))
    for missing in EXPECTED_MISSING:
        assert missing not in files, f"Corrupted frame {missing} should have been deleted."
    assert len(files) == 56, f"Expected 56 frames, found {len(files)}."
    for filename in EXPECTED_VALID:
        assert filename in files, f"Expected valid frame {filename} is missing."
    assert files == EXPECTED_VALID, "Frames directory contains unexpected files."

    # Decode every submitted JPEG and compare it to the corresponding frame
    # independently extracted from the source video.
    for filename in sorted(EXPECTED_VALID):
        submitted = os.path.join(FRAMES_DIR, filename)
        info = probe(submitted, reference_path(filename))
        assert info["width"] == 640 and info["height"] == 480, (
            f"{filename} has incorrect dimensions."
        )
        assert info["average"] >= 5.0, f"{filename} is itself a black/corrupt frame."
        assert info["mae"] <= 3.0, (
            f"{filename} does not match its source-video frame (grayscale MAE={info['mae']})."
        )


def test_corrupted_frames_log():
    assert os.path.exists(CORRUPTED_LOG), f"Log file {CORRUPTED_LOG} does not exist."
    with open(CORRUPTED_LOG, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]
    assert set(lines) == EXPECTED_MISSING, (
        f"Log file contents {set(lines)} do not match expected {EXPECTED_MISSING}."
    )
    assert len(lines) == len(EXPECTED_MISSING), "Corrupted-frame log contains duplicates."


def read_and_validate_database():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='frame_features'")
        assert cursor.fetchone() is not None, "Table 'frame_features' does not exist."

        cursor.execute("PRAGMA table_info(frame_features)")
        schema = cursor.fetchall()
        assert [row[1] for row in schema] == ["filename"] + [f"bin{i}" for i in range(8)]
        assert schema[0][2].upper() == "TEXT" and schema[0][5] == 1, (
            "filename must be the TEXT primary key."
        )
        for row in schema[1:]:
            assert row[2].upper() == "REAL", f"Column {row[1]} must be REAL."

        cursor.execute("SELECT COUNT(*) FROM frame_features")
        count = cursor.fetchone()[0]
        assert count == 56, f"Expected 56 rows in frame_features, found {count}."

        cursor.execute(
            "SELECT filename, bin0, bin1, bin2, bin3, bin4, bin5, bin6, bin7 "
            "FROM frame_features"
        )
        rows = cursor.fetchall()
    finally:
        conn.close()

    db_features = {}
    assert {row[0] for row in rows} == EXPECTED_VALID, (
        "Database filenames do not exactly match the cleaned frame set."
    )
    for row in rows:
        filename = row[0]
        values = row[1:]
        assert all(isinstance(v, (int, float)) and math.isfinite(v) for v in values)
        assert all(-1e-12 <= float(v) <= 1.0 + 1e-12 for v in values)
        assert math.isclose(sum(values), 1.0, rel_tol=0, abs_tol=1e-7), (
            f"Histogram for {filename} is not normalized."
        )
        actual = probe(os.path.join(FRAMES_DIR, filename))["histogram"]
        for index, (stored, calculated) in enumerate(zip(values, actual)):
            assert math.isclose(float(stored), calculated, rel_tol=0, abs_tol=1e-7), (
                f"Incorrect bin{index} for {filename}: stored {stored}, expected {calculated}."
            )
        db_features[filename] = tuple(float(v) for v in values)
    return db_features


def test_sqlite_database():
    read_and_validate_database()


def test_service_unauthorized():
    payload = {"target_frame": "frame_0005.jpg", "top_k": 2, "token": "bad-token"}
    try:
        response = requests.post(SERVICE_URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to service: {exc}")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized, got {response.status_code}."
    )


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def test_service_authorized_search():
    features = read_and_validate_database()
    filenames = sorted(features)

    # Exercise every possible target. Varying k prevents a shape-only response,
    # while tie-aware checks permit any valid ordering among equal distances.
    for index, target in enumerate(filenames):
        top_k = 1 + (index % 7)
        payload = {
            "target_frame": target,
            "top_k": top_k,
            "token": "data-sci-auth-77",
        }
        try:
            response = requests.post(SERVICE_URL, json=payload, timeout=2)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to service for {target}: {exc}")

        assert response.status_code == 200, (
            f"Expected 200 OK for {target}, got {response.status_code}: {response.text}"
        )
        try:
            data = response.json()
        except (ValueError, json.JSONDecodeError):
            pytest.fail(f"Response for {target} is not valid JSON.")

        assert "results" in data, "Response JSON missing 'results' key."
        results = data["results"]
        assert isinstance(results, list), "'results' should be a list."
        assert len(results) == top_k, f"Expected {top_k} results, got {len(results)}."
        assert target not in results, "Target frame should not be in the results."
        assert len(set(results)) == len(results), "Search results must not contain duplicates."
        assert all(name in features for name in results), "Search returned an invalid frame."

        ranked_distances = sorted(
            distance(features[target], hist)
            for name, hist in features.items() if name != target
        )
        cutoff = ranked_distances[top_k - 1]
        strictly_closer = {
            name for name, hist in features.items()
            if name != target and distance(features[target], hist) < cutoff - 1e-10
        }
        assert strictly_closer.issubset(set(results)), (
            f"Search for {target} omitted a frame strictly closer than its returned cutoff."
        )
        for name in results:
            result_distance = distance(features[target], features[name])
            assert result_distance <= cutoff + 1e-10, (
                f"Search for {target} returned {name} at distance {result_distance}, "
                f"outside the true top-{top_k} cutoff {cutoff}."
            )
PY_EOF

if [ "$status" -eq 0 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
    status=$?
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
