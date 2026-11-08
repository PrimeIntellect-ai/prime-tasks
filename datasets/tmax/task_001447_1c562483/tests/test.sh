#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest


def natural_key(path):
    return [int(part) if part.isdigit() else part.lower()
            for part in re.split(r"(\d+)", os.path.basename(path))]


def run_checked(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)


def test_step1_video_extraction():
    frames_dir = "/home/user/frames"
    count_file = "/home/user/frame_count.txt"
    video = "/app/data_feed.mp4"

    assert os.path.isdir(frames_dir), f"Frames directory does not exist at {frames_dir}."
    assert os.path.isfile(count_file), f"Frame count file does not exist at {count_file}."

    jpegs = glob.glob(os.path.join(frames_dir, "*.jpg")) + glob.glob(os.path.join(frames_dir, "*.jpeg"))
    assert len(jpegs) > 0, "No JPEG frames found in the frames directory."

    with open(count_file, "r") as f:
        count_str = f.read().strip()
    assert count_str.isdigit(), "Frame count file does not contain a valid integer."
    assert int(count_str) == len(jpegs), "Frame count does not match the number of JPEG files."
    assert len(jpegs) == 60, f"Expected exactly 60 frames at 1 fps, found {len(jpegs)}."
    assert int(count_str) == 60, "frame_count.txt must contain 60."

    # Derive the expected 1-fps frames directly from the supplied video.
    width, height = 320, 240
    frame_size = width * height * 3
    expected_raw = run_checked([
        "ffmpeg", "-v", "error", "-i", video, "-vf", "fps=1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ]).stdout
    assert len(expected_raw) == 60 * frame_size, "The supplied video did not decode to the expected 60 one-fps frames."
    expected = [expected_raw[i:i + frame_size]
                for i in range(0, len(expected_raw), frame_size)]

    # JPEG compression may vary, so compare sampled decoded pixels with a
    # tolerance while requiring a one-to-one match to all 60 source frames.
    sample_positions = list(range(0, frame_size, 113))
    expected_samples = [bytes(frame[i] for i in sample_positions) for frame in expected]
    matched = set()

    for image in sorted(jpegs, key=natural_key):
        probe = run_checked([
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=codec_name,width,height",
            "-of", "json", image
        ])
        info = json.loads(probe.stdout.decode("utf-8"))
        streams = info.get("streams", [])
        assert len(streams) == 1, f"{image} is not a decodable single-image JPEG."
        stream = streams[0]
        assert stream.get("codec_name") == "mjpeg", f"{image} is not actually a JPEG image."
        assert (stream.get("width"), stream.get("height")) == (width, height), f"{image} has incorrect dimensions."

        raw = run_checked([
            "ffmpeg", "-v", "error", "-i", image, "-frames:v", "1",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
        ]).stdout
        assert len(raw) == frame_size, f"{image} could not be decoded as one complete frame."
        sample = bytes(raw[i] for i in sample_positions)

        distances = []
        for idx, reference in enumerate(expected_samples):
            distance = sum(abs(a - b) for a, b in zip(sample, reference)) / len(sample)
            distances.append((distance, idx))
        distance, idx = min(distances)
        assert distance <= 15.0, f"{image} does not correspond to a 1-fps frame from /app/data_feed.mp4."
        assert idx not in matched, f"Duplicate source frame detected in {image}."
        matched.add(idx)

    assert matched == set(range(60)), "The JPEG set does not contain every frame from the 1-fps extraction."


def apply_and_check_indexes(conn, sql_script):
    before_nodes = conn.execute("SELECT * FROM nodes ORDER BY id").fetchall()
    before_logs = conn.execute("SELECT * FROM traffic_logs ORDER BY id").fetchall()
    conn.executescript(sql_script)
    assert conn.execute("SELECT * FROM nodes ORDER BY id").fetchall() == before_nodes
    assert conn.execute("SELECT * FROM traffic_logs ORDER BY id").fetchall() == before_logs

    indexes = conn.execute("PRAGMA index_list('traffic_logs')").fetchall()
    user_indexes = [row for row in indexes if not row[1].startswith("sqlite_autoindex")]
    assert len(user_indexes) == 1, "indexes.sql must create exactly the one needed traffic_logs index."
    index_row = user_indexes[0]
    index_name = index_row[1]
    assert index_row[2] == 0, "The optimization index must not be UNIQUE."
    assert index_row[4] == 0, "The optimization index must not be partial."
    columns = tuple(row[2] for row in conn.execute(f"PRAGMA index_info('{index_name}')"))
    assert columns == ("timestamp", "source_node_id", "bytes_transferred"), (
        "Expected a covering index on traffic_logs(timestamp, source_node_id, bytes_transferred)."
    )

    plan = conn.execute("""
        EXPLAIN QUERY PLAN
        SELECT n.region, SUM(t.bytes_transferred)
        FROM nodes n
        JOIN traffic_logs t ON n.id = t.source_node_id
        WHERE t.timestamp >= '2024-01-01' AND t.timestamp < '2024-02-01'
        GROUP BY n.region
    """).fetchall()
    plan_str = " ".join(row[-1] for row in plan).upper()
    assert "INDEX" in plan_str, "No index was used in the query plan after applying indexes.sql."
    assert index_name.upper() in plan_str, "The requested query does not use the submitted traffic_logs index."
    assert "COVERING INDEX" in plan_str, "The traffic_logs index is not covering the aggregation query."


def test_step2_database_indexes():
    sql_file = "/home/user/indexes.sql"
    assert os.path.isfile(sql_file), f"SQL file does not exist at {sql_file}."
    with open(sql_file, "r") as f:
        sql_script = f.read()

    # Preserve the original execution check against a copy of the supplied DB.
    test_db = "/tmp/test_metrics.db"
    if os.path.exists(test_db):
        os.remove(test_db)
    shutil.copy2("/app/metrics.db", test_db)
    conn = sqlite3.connect(test_db)
    try:
        conn.executescript(sql_script)
        plan = conn.execute("""
            EXPLAIN QUERY PLAN
            SELECT n.region, SUM(t.bytes_transferred)
            FROM nodes n JOIN traffic_logs t ON n.id = t.source_node_id
            WHERE t.timestamp >= '2024-01-01' AND t.timestamp < '2024-02-01'
            GROUP BY n.region
        """).fetchall()
        assert "INDEX" in " ".join(row[-1] for row in plan).upper()
    except Exception as exc:
        pytest.fail(f"Failed to execute or use indexes.sql: {exc}")
    finally:
        conn.close()

    # Validate the actual index shape and covering strategy on a pristine DB.
    conn = sqlite3.connect(":memory:")
    conn.executescript("""
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, hostname TEXT, region TEXT);
        CREATE TABLE traffic_logs (
            id INTEGER PRIMARY KEY,
            source_node_id INTEGER,
            target_node_id INTEGER,
            bytes_transferred INTEGER,
            timestamp TEXT
        );
        INSERT INTO nodes VALUES (1, 'h1', 'r1'), (2, 'h2', 'r2');
        INSERT INTO traffic_logs VALUES
            (1, 1, 2, 100, '2024-01-02'),
            (2, 2, 1, 200, '2024-01-03'),
            (3, 1, 2, 300, '2025-01-03');
    """)
    try:
        apply_and_check_indexes(conn, sql_script)
    except Exception as exc:
        pytest.fail(f"Invalid index strategy: {exc}")
    finally:
        conn.close()


def invoke_filter(script, input_dir, output_dir):
    result = subprocess.run(
        ["python3", script, input_dir, output_dir],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"Script failed with exit code {result.returncode}:\n{result.stderr}"


def test_step3_adversarial_corpus():
    script = "/home/user/validate_graphs.py"
    assert os.path.isfile(script), f"Script missing at {script}"
    assert os.access(script, os.X_OK), "validate_graphs.py is not executable."

    # Preserve checks against the supplied corpora, including byte-for-byte copies.
    for label, should_copy in (("evil", False), ("clean", True)):
        input_dir = f"/app/corpora/{label}"
        output_dir = f"/tmp/test_{label}"
        shutil.rmtree(output_dir, ignore_errors=True)
        os.makedirs(output_dir)
        invoke_filter(script, input_dir, output_dir)
        input_files = {f for f in os.listdir(input_dir) if f.endswith(".json")}
        output_files = set(os.listdir(output_dir))
        if should_copy:
            assert output_files == input_files, "Clean corpus was modified, rejected, or supplemented."
            for name in input_files:
                assert open(os.path.join(input_dir, name), "rb").read() == open(os.path.join(output_dir, name), "rb").read()
        else:
            assert not output_files.intersection(input_files), "An evil corpus file bypassed the filter."

    # Build a fresh mixed corpus with randomized paths and names so the script
    # must implement schema and centrality analysis rather than recognize fixtures.
    root = tempfile.mkdtemp(prefix="graph_filter_" + uuid.uuid4().hex + "_")
    input_dir = os.path.join(root, uuid.uuid4().hex)
    output_dir = os.path.join(root, uuid.uuid4().hex)
    os.makedirs(input_dir)
    os.makedirs(output_dir)

    rng = random.SystemRandom()
    expected = {}

    def add_json(value, accepted):
        name = uuid.uuid4().hex + ".json"
        path = os.path.join(input_dir, name)
        payload = json.dumps(value, separators=(",", ":"), sort_keys=False).encode("utf-8")
        with open(path, "wb") as f:
            f.write(payload)
        if accepted:
            expected[name] = payload

    # Valid low-centrality cycles and paths.
    n = rng.randint(7, 12)
    ids = [uuid.uuid4().hex for _ in range(n)]
    add_json({
        "nodes": [{"id": x} for x in ids],
        "edges": [{"source": ids[i], "target": ids[(i + 1) % n]} for i in range(n)]
    }, True)
    ids2 = [uuid.uuid4().hex for _ in range(6)]
    add_json({
        "nodes": [{"id": x} for x in ids2],
        "edges": [{"source": ids2[i], "target": ids2[i + 1]} for i in range(5)]
    }, True)

    # Stars and an exact-threshold graph must be rejected.
    ids3 = [uuid.uuid4().hex for _ in range(rng.randint(6, 10))]
    add_json({
        "nodes": [{"id": x} for x in ids3],
        "edges": [{"source": ids3[0], "target": x} for x in ids3[1:]]
    }, False)
    ids4 = [uuid.uuid4().hex for _ in range(6)]
    add_json({
        "nodes": [{"id": x} for x in ids4],
        "edges": [{"source": ids4[0], "target": ids4[i]} for i in range(1, 5)]
    }, False)

    # Independently malformed schema and JSON cases.
    add_json({"edges": []}, False)
    add_json({"nodes": [], "edges": [{"source": "x"}]}, False)
    add_json({"nodes": [{"id": 7}], "edges": []}, False)
    add_json({"nodes": ["not-a-dictionary"], "edges": []}, False)
    add_json({"nodes": [], "edges": "not-a-list"}, False)
    malformed_name = uuid.uuid4().hex + ".json"
    with open(os.path.join(input_dir, malformed_name), "wb") as f:
        f.write(b'{"nodes": [')
    with open(os.path.join(input_dir, uuid.uuid4().hex + ".txt"), "w") as f:
        f.write("ignore me")

    invoke_filter(script, input_dir, output_dir)
    assert set(os.listdir(output_dir)) == set(expected), "Dynamic corpus filtering produced the wrong output set."
    for name, payload in expected.items():
        with open(os.path.join(output_dir, name), "rb") as f:
            assert f.read() == payload, f"Accepted graph {name} was not copied unmodified."

    # The CLI must accept exactly two arguments.
    missing = subprocess.run(["python3", script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    extra = subprocess.run(["python3", script, input_dir, output_dir, "extra"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert missing.returncode != 0, "Script accepted no input/output arguments."
    assert extra.returncode != 0, "Script accepted more than two arguments."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
