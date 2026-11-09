#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
from collections import defaultdict
import pytest


def generate_random_csv(num_rows):
    lines = ["timestamp,video_pkt_size,audio_pkt_size,subtitle_pkt_size,data_pkt_size"]
    for i in range(num_rows):
        timestamp = round(random.uniform(0.0, 100.0), 6)
        row = [f"{timestamp:.6f}"]
        for _ in range(4):
            if random.random() < 0.3:
                row.append("")
            else:
                row.append(str(random.randint(1, 100000)))
        lines.append(",".join(row))
    return "\n".join(lines)


def test_fuzz_equivalence():
    agent_script = "/home/user/reshape_stats.py"
    oracle_script = "/tests/oracle_reshape.py"

    assert os.path.isfile(agent_script), f"Agent script missing or not a file: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    with open(agent_script, "rb") as agent_file, open(oracle_script, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent script must not be a byte-identical copy of the reference"

    random.seed(42)

    for i in range(200):
        num_rows = random.randint(0, 1000)
        csv_data = generate_random_csv(num_rows)

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=csv_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}. Stderr: {oracle_proc.stderr}"

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=csv_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr}"

        try:
            oracle_json = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle output invalid JSON on iteration {i}")

        try:
            agent_json = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent output invalid JSON on iteration {i}. Output: {agent_proc.stdout}")

        assert agent_json == oracle_json, (
            f"Mismatch on iteration {i}.\n"
            f"Input CSV rows: {num_rows}\n"
            f"Oracle output: {oracle_json}\n"
            f"Agent output: {agent_json}"
        )


def test_stream_summary_exists_and_valid():
    summary_path = "/home/user/stream_summary.json"
    assert os.path.exists(summary_path), f"Missing final output file: {summary_path}"

    with open(summary_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{summary_path} does not contain valid JSON")

    assert isinstance(data, list), f"{summary_path} should contain a JSON array"

    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-show_packets",
            "-show_entries", "packet=codec_type,size",
            "-of", "json", "/app/stream.mp4"
        ],
        text=True,
        capture_output=True
    )
    assert probe.returncode == 0, f"ffprobe failed: {probe.stderr}"

    try:
        packets = json.loads(probe.stdout).get("packets", [])
    except json.JSONDecodeError:
        pytest.fail("ffprobe returned invalid JSON")

    stats = defaultdict(list)
    for packet in packets:
        stream_type = packet.get("codec_type")
        if stream_type not in ("video", "audio"):
            continue
        try:
            size = int(packet.get("size", 0))
        except (TypeError, ValueError):
            continue
        if size > 0:
            stats[stream_type].append(size)

    expected = []
    for stream_type in sorted(stats):
        sizes = stats[stream_type]
        expected.append({
            "stream_type": stream_type,
            "max": max(sizes),
            "avg": f"{sum(sizes) / len(sizes):.2f}"
        })

    assert expected, "No video or audio packets were found in /app/stream.mp4"
    assert data == expected, (
        "stream_summary.json does not summarize the actual video/audio packets "
        f"from /app/stream.mp4. Expected {expected}, got {data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
