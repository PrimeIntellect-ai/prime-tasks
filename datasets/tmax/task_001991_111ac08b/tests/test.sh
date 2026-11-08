#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import os
import re
import sqlite3
import subprocess
import tempfile

import pytest

OUTPUT_FILE = "/home/user/total_distance.txt"
SQL_FILE = "/home/user/export_edges.sql"
DB_FILE = "/home/user/network.db"
VIDEO_FILE = "/app/routing_sim.mp4"


def read_agent_value():
    assert os.path.exists(OUTPUT_FILE), f"The file {OUTPUT_FILE} does not exist."
    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()
    try:
        return int(content)
    except ValueError:
        pytest.fail(
            f"Could not parse the content of {OUTPUT_FILE} as an integer. "
            f"Content: '{content}'"
        )


@functools.lru_cache(maxsize=1)
def extract_video_path():
    assert os.path.isfile(VIDEO_FILE), f"The video {VIDEO_FILE} does not exist."

    with tempfile.TemporaryDirectory() as frame_dir:
        pattern = os.path.join(frame_dir, "%03d.png")
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", VIDEO_FILE, "-vf", "fps=1", pattern],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"ffmpeg could not decode the video: {result.stderr}"

        frames = sorted(
            os.path.join(frame_dir, name)
            for name in os.listdir(frame_dir)
            if name.endswith(".png")
        )
        assert len(frames) == 5, f"Expected 5 one-second video frames, found {len(frames)}"

        node_ids = []
        for frame in frames:
            ocr = subprocess.run(
                [
                    "tesseract", frame, "stdout", "--psm", "10",
                    "-c", "tessedit_char_whitelist=0123456789",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert ocr.returncode == 0, f"tesseract failed on {frame}: {ocr.stderr}"
            digits = re.sub(r"\D", "", ocr.stdout)
            assert digits, f"Could not OCR a Node ID from video frame {frame}"
            node_ids.append(int(digits))

    assert node_ids == [1, 3, 5, 2, 4], f"Unexpected Node ID sequence decoded from video: {node_ids}"
    return node_ids


@functools.lru_cache(maxsize=1)
def database_links():
    assert os.path.isfile(DB_FILE), f"The database {DB_FILE} does not exist."
    conn = sqlite3.connect(f"file:{DB_FILE}?mode=ro", uri=True)
    try:
        rows = conn.execute(
            "SELECT source_id, target_id, distance FROM links ORDER BY rowid"
        ).fetchall()
    finally:
        conn.close()

    expected_fixture = [(1, 3, 15), (3, 5, 20), (5, 2, 10), (2, 4, 35), (4, 1, 50)]
    assert rows == expected_fixture, f"The network links fixture was unexpectedly modified: {rows}"
    return rows


def test_total_distance_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"The file {OUTPUT_FILE} does not exist."


def test_total_distance_value():
    agent_val = read_agent_value()
    target_value = 80
    error = abs(agent_val - target_value)
    assert error == 0, (
        f"Expected total distance {target_value}, but got {agent_val}. "
        f"Absolute error: {error} (Threshold: <= 0)"
    )


def test_export_edges_sql_is_corrected_and_executable():
    assert os.path.isfile(SQL_FILE), f"The SQL file {SQL_FILE} does not exist."
    with open(SQL_FILE, "r") as f:
        sql = f.read().strip()
    assert sql, f"The SQL file {SQL_FILE} is empty."

    conn = sqlite3.connect(f"file:{DB_FILE}?mode=ro", uri=True)
    try:
        conn.execute("PRAGMA query_only = ON")
        try:
            cursor = conn.execute(sql)
            actual = cursor.fetchall()
        except sqlite3.Error as exc:
            pytest.fail(f"The corrected SQL query could not be executed: {exc}")
    finally:
        conn.close()

    expected = database_links()
    assert len(actual) == len(expected), (
        f"The edge query returned {len(actual)} rows instead of {len(expected)}; "
        "it may still contain a cross join."
    )
    assert sorted(actual) == sorted(expected), (
        f"The edge query returned incorrect edges. Expected {expected}, got {actual}"
    )


def test_total_matches_video_path_and_database_edges():
    path = extract_video_path()
    links = database_links()
    edge_distances = {(source, target): distance for source, target, distance in links}

    expected_total = 0
    for source, target in zip(path, path[1:]):
        assert (source, target) in edge_distances, (
            f"No database edge exists for video transition {source} -> {target}"
        )
        expected_total += edge_distances[(source, target)]

    agent_val = read_agent_value()
    assert agent_val == expected_total, (
        f"Expected total distance {expected_total} derived from the decoded video path "
        f"and database links, but got {agent_val}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
