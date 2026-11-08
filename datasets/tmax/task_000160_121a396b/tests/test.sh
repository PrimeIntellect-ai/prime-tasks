#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import time
import pytest

HOME = "/home/user"
CONFIGS = os.path.join(HOME, "configs")


def get_db_configs():
    conn = sqlite3.connect("/data/configs.db")
    c = conn.cursor()
    c.execute("SELECT id, content FROM snapshots ORDER BY id")
    rows = c.fetchall()
    conn.close()
    return rows


def parse_config(content):
    cfg = {}
    for line in content.strip().split('\n'):
        if '=' in line:
            k, v = line.split('=', 1)
            cfg[k] = v
    return cfg


def is_sensitive(key):
    k = key.lower()
    return 'secret' in k or 'password' in k or 'token' in k


def compute_diff(cfg1, cfg2):
    added = 0
    removed = 0
    modified = 0
    secrets_masked = 0

    keys1 = set(cfg1.keys())
    keys2 = set(cfg2.keys())

    for k in keys2 - keys1:
        if is_sensitive(k):
            secrets_masked += 1
        else:
            added += 1

    for k in keys1 - keys2:
        if is_sensitive(k):
            secrets_masked += 1
        else:
            removed += 1

    for k in keys1 & keys2:
        if cfg1[k] != cfg2[k]:
            if is_sensitive(k):
                secrets_masked += 1
            else:
                modified += 1

    return added, removed, modified, secrets_masked


def expected_output():
    rows = get_db_configs()
    expected_lines = []
    total_a = total_r = total_m = total_s = 0

    for i in range(len(rows) - 1):
        id1, c1 = rows[i]
        id2, c2 = rows[i + 1]
        a, r, m, s = compute_diff(parse_config(c1), parse_config(c2))
        total_a += a
        total_r += r
        total_m += m
        total_s += s
        expected_lines.append(
            f"{id1}.txt -> {id2}.txt: added: {a}, removed: {r}, "
            f"modified: {m}, secrets_masked: {s}"
        )

    expected_lines.append(
        f"TOTAL: added: {total_a}, removed: {total_r}, "
        f"modified: {total_m}, secrets_masked: {total_s}"
    )
    return "\n".join(expected_lines) + "\n"


def test_pipeline_artifacts():
    pipeline = os.path.join(HOME, "pipeline.sh")
    source = os.path.join(HOME, "fast_tracker.c")
    assert os.path.isfile(pipeline), "pipeline.sh missing"
    assert os.path.isfile(source), "fast_tracker.c missing"
    assert os.path.getsize(pipeline) > 0, "pipeline.sh is empty"
    assert os.path.getsize(source) > 0, "fast_tracker.c is empty"

    # Force the submitted pipeline to perform export, compilation, processing,
    # and logging rather than accepting artifacts prepared by another program.
    os.makedirs(CONFIGS, exist_ok=True)
    for name in os.listdir(CONFIGS):
        path = os.path.join(CONFIGS, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    for path in (os.path.join(HOME, "fast_tracker"),
                 os.path.join(HOME, "summary_stats.log"),
                 os.path.join(HOME, "pipeline.log")):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    result = subprocess.run(
        ["bash", pipeline], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}: {result.stderr}"
    )

    assert os.path.exists(pipeline), "pipeline.sh missing"
    assert os.path.exists(os.path.join(HOME, "pipeline.log")), "pipeline.log missing"
    assert os.path.exists(source), "fast_tracker.c missing"
    assert os.path.exists(os.path.join(HOME, "fast_tracker")), "fast_tracker binary missing"
    assert os.path.exists(os.path.join(HOME, "summary_stats.log")), "summary_stats.log missing"

    binary = os.path.join(HOME, "fast_tracker")
    assert os.path.isfile(binary), "fast_tracker is not a regular file"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_tracker is not a compiled ELF binary"

    rows = get_db_configs()
    exported = {}
    for name in os.listdir(CONFIGS):
        if not name.endswith(".txt"):
            continue
        stem = name[:-4]
        assert stem.isdigit(), f"non-numeric config filename: {name}"
        numeric_id = int(stem)
        assert numeric_id not in exported, f"duplicate numeric config ID: {numeric_id}"
        exported[numeric_id] = os.path.join(CONFIGS, name)

    assert len(exported) == 2000, "Expected 2000 config files extracted"
    assert set(exported) == {row[0] for row in rows}, "Exported snapshot IDs do not match the database"
    for snapshot_id, content in rows:
        with open(exported[snapshot_id], "r") as f:
            assert f.read() == content, f"Exported content for snapshot {snapshot_id} is incorrect"

    with open(os.path.join(HOME, "pipeline.log"), "r") as f:
        log_lines = [line.strip().lower() for line in f if line.strip()]

    def event_index(phase, words):
        for i, line in enumerate(log_lines):
            if phase in line and any(word in line for word in words):
                return i
        return None

    export_start = event_index("export", ("start", "begin"))
    export_end = event_index("export", ("complete", "finish", "end"))
    process_start = event_index("process", ("start", "begin"))
    process_end = event_index("process", ("complete", "finish", "end"))
    assert None not in (export_start, export_end, process_start, process_end), \
        "pipeline.log must record start and completion of EXPORT and PROCESS"
    assert export_start <= export_end <= process_start <= process_end, \
        "pipeline.log phase events are not in workflow order"
    assert any(re.search(r"\d", line) for line in log_lines), \
        "pipeline.log does not contain any recorded time"


def test_summary_stats_correctness():
    expected = expected_output()
    with open(os.path.join(HOME, "summary_stats.log"), "r") as f:
        agent_output = f.read()
    assert agent_output.strip() == expected.strip(), \
        "summary_stats.log content does not match expected output exactly."

    result = subprocess.run(
        [os.path.join(HOME, "fast_tracker"), CONFIGS],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, \
        f"fast_tracker failed with exit code {result.returncode}: {result.stderr}"
    assert result.stdout.strip() == expected.strip(), \
        "fast_tracker output does not match the required summary"


def test_speedup_metric():
    assert os.path.exists(CONFIGS), "configs directory missing"

    files = sorted(
        [f for f in os.listdir(CONFIGS) if f.endswith('.txt')],
        key=lambda x: int(x.split('.')[0])
    )
    assert len(files) == 2000, "Expected 2000 config files extracted"

    start_baseline = time.perf_counter()
    for i in range(min(100, len(files) - 1)):
        f1 = os.path.join(CONFIGS, files[i])
        f2 = os.path.join(CONFIGS, files[i + 1])
        subprocess.run(
            ["/app/config_diff_oracle", f1, f2],
            stdout=subprocess.DEVNULL, check=True
        )
    end_baseline = time.perf_counter()

    baseline_time = (end_baseline - start_baseline) * (1999 / 100.0)

    start_agent = time.perf_counter()
    result = subprocess.run(
        [os.path.join(HOME, "fast_tracker"), CONFIGS],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=30
    )
    agent_time = time.perf_counter() - start_agent
    assert result.returncode == 0, "fast_tracker failed during speed measurement"

    speedup = baseline_time / agent_time if agent_time > 0 else float('inf')
    assert speedup >= 10.0, \
        f"Speedup metric failed: measured speedup is {speedup:.2f}x, threshold is 10.0x"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
