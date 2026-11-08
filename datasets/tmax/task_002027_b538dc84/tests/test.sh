#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

import numpy as np
import pytest

RUN_INFERENCE = "/home/user/run_inference.py"
ORGANIZE = "/home/user/organize.sh"
DB_PATH = "/home/user/experiment_tracking.db"


def expected_mean(exp_dir):
    with open(os.path.join(exp_dir, "architecture.json"), "r") as f:
        arch = json.load(f)

    X = np.loadtxt(os.path.join(exp_dir, "features.csv"), delimiter=",")
    with np.load(os.path.join(exp_dir, "weights.npz")) as weights:
        W1 = weights["W1"]
        b1 = weights["b1"]
        W2 = weights["W2"]
        b2 = weights["b2"]

    assert X.shape == (50, arch["input_dim"])
    assert W1.shape == (arch["input_dim"], arch["hidden_dim"])
    assert b1.shape == (arch["hidden_dim"],)
    assert W2.shape == (arch["hidden_dim"], arch["output_dim"])
    assert b2.shape == (arch["output_dim"],)

    return float(np.mean(np.maximum(0.0, X @ W1 + b1) @ W2 + b2))


def run_submission_inference(exp_dir):
    proc = subprocess.run(
        ["python3", RUN_INFERENCE, exp_dir],
        text=True,
        capture_output=True,
        timeout=20,
        check=True,
    )
    output = proc.stdout.strip()
    float_pattern = r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
    assert re.fullmatch(float_pattern, output), (
        "run_inference.py must print only one finite float to standard output; "
        f"got {proc.stdout!r}"
    )
    value = float(output)
    assert np.isfinite(value)
    return value


def test_required_scripts_exist_and_inference_is_correct():
    assert os.path.isfile(RUN_INFERENCE), f"{RUN_INFERENCE} does not exist"
    assert stat.S_ISREG(os.stat(RUN_INFERENCE).st_mode), f"{RUN_INFERENCE} is not a regular file"
    assert os.path.isfile(ORGANIZE), f"{ORGANIZE} does not exist"
    assert stat.S_ISREG(os.stat(ORGANIZE).st_mode), f"{ORGANIZE} is not a regular file"

    locations = {
        "exp_alpha": "/home/user/organized_data/positive/exp_alpha",
        "exp_beta": "/home/user/organized_data/negative/exp_beta",
        "exp_gamma": "/home/user/organized_data/positive/exp_gamma",
    }
    for name, exp_dir in locations.items():
        assert os.path.isdir(exp_dir), f"Missing experiment directory for {name}"
        actual = run_submission_inference(exp_dir)
        expected = expected_mean(exp_dir)
        assert actual == pytest.approx(expected, rel=1e-9, abs=1e-9), (
            f"run_inference.py returned the wrong mean for {name}"
        )


def test_directories_moved_correctly():
    pos_dir = "/home/user/organized_data/positive"
    neg_dir = "/home/user/organized_data/negative"

    assert os.path.isdir(pos_dir), f"{pos_dir} does not exist"
    assert os.path.isdir(neg_dir), f"{neg_dir} does not exist"

    assert os.path.isdir(os.path.join(pos_dir, "exp_alpha")), "exp_alpha should be in positive directory"
    assert os.path.isdir(os.path.join(pos_dir, "exp_gamma")), "exp_gamma should be in positive directory"
    assert os.path.isdir(os.path.join(neg_dir, "exp_beta")), "exp_beta should be in negative directory"

    assert not os.path.exists("/home/user/experiments/exp_alpha"), "exp_alpha should have been moved"
    assert not os.path.exists("/home/user/experiments/exp_beta"), "exp_beta should have been moved"
    assert not os.path.exists("/home/user/experiments/exp_gamma"), "exp_gamma should have been moved"


def test_database_entries():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='results';")
    assert cursor.fetchone() is not None, "Table 'results' does not exist in the database"

    cursor.execute("SELECT experiment_name FROM results WHERE mean_score > 0 ORDER BY experiment_name;")
    pos_results = [row[0] for row in cursor.fetchall()]
    assert pos_results == ["exp_alpha", "exp_gamma"], "Positive results in database do not match expected"

    cursor.execute("SELECT experiment_name FROM results WHERE mean_score <= 0 ORDER BY experiment_name;")
    neg_results = [row[0] for row in cursor.fetchall()]
    assert neg_results == ["exp_beta"], "Negative results in database do not match expected"

    locations = {
        "exp_alpha": "/home/user/organized_data/positive/exp_alpha",
        "exp_beta": "/home/user/organized_data/negative/exp_beta",
        "exp_gamma": "/home/user/organized_data/positive/exp_gamma",
    }
    for name, exp_dir in locations.items():
        cursor.execute("SELECT mean_score FROM results WHERE experiment_name = ?", (name,))
        rows = cursor.fetchall()
        assert len(rows) == 1, f"Expected exactly one database row for {name}"
        stored = rows[0][0]
        assert stored is not None and np.isfinite(float(stored))
        assert float(stored) == pytest.approx(expected_mean(exp_dir), rel=1e-9, abs=1e-9), (
            f"Stored mean_score is incorrect for {name}"
        )

    conn.close()


def make_probe(exp_dir, rng, desired_mean):
    input_dim, hidden_dim, output_dim = 3, 5, 1
    os.makedirs(exp_dir)
    with open(os.path.join(exp_dir, "architecture.json"), "w") as f:
        json.dump({
            "input_dim": input_dim,
            "hidden_dim": hidden_dim,
            "output_dim": output_dim,
        }, f)

    X = rng.normal(size=(50, input_dim))
    W1 = rng.normal(size=(input_dim, hidden_dim))
    b1 = rng.normal(size=hidden_dim)
    W2 = rng.normal(size=(hidden_dim, output_dim))
    base = np.maximum(0.0, X @ W1 + b1) @ W2
    b2 = np.array([desired_mean - float(np.mean(base))])

    np.savetxt(os.path.join(exp_dir, "features.csv"), X, delimiter=",")
    np.savez(os.path.join(exp_dir, "weights.npz"), W1=W1, b1=b1, W2=W2, b2=b2)


def test_organize_pipeline_on_fresh_derived_inputs():
    token = uuid.uuid4().hex
    names = [f"probe_positive_{token}", f"probe_negative_{token}"]
    source_root = "/home/user/experiments"
    os.makedirs(source_root, exist_ok=True)

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    make_probe(os.path.join(source_root, names[0]), rng, 1.25)
    make_probe(os.path.join(source_root, names[1]), rng, -0.75)

    expected = {
        name: expected_mean(os.path.join(source_root, name))
        for name in names
    }
    assert expected[names[0]] > 0
    assert expected[names[1]] <= 0

    with open(RUN_INFERENCE, "rb") as f:
        original_inference = f.read()
    original_mode = stat.S_IMODE(os.stat(RUN_INFERENCE).st_mode)

    saved_fd, saved_path = tempfile.mkstemp(prefix="submitted_inference_", suffix=".py")
    os.close(saved_fd)
    with open(saved_path, "wb") as f:
        f.write(original_inference)
    os.chmod(saved_path, original_mode)

    marker = os.path.join("/tmp", f"inference_calls_{token}")
    wrapper = f'''#!/usr/bin/env python3
import os
import sys
with open({marker!r}, "a") as marker_file:
    marker_file.write(os.path.basename(sys.argv[1]) + "\\n")
os.execv(sys.executable, [sys.executable, {saved_path!r}] + sys.argv[1:])
'''

    try:
        with open(RUN_INFERENCE, "w") as f:
            f.write(wrapper)
        os.chmod(RUN_INFERENCE, original_mode)

        proc = subprocess.run(
            ["bash", ORGANIZE],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert proc.returncode == 0, (
            f"organize.sh failed on fresh experiments:\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )

        calls = []
        if os.path.isfile(marker):
            with open(marker, "r") as f:
                calls = [line.strip() for line in f if line.strip()]
        assert sorted(calls) == sorted(names), (
            "organize.sh must call /home/user/run_inference.py once for each experiment"
        )

        destinations = {
            names[0]: f"/home/user/organized_data/positive/{names[0]}",
            names[1]: f"/home/user/organized_data/negative/{names[1]}",
        }
        for name in names:
            assert not os.path.exists(os.path.join(source_root, name))
            assert os.path.isdir(destinations[name]), f"{name} was moved to the wrong location"

        conn = sqlite3.connect(DB_PATH)
        try:
            for name in names:
                rows = conn.execute(
                    "SELECT mean_score FROM results WHERE experiment_name = ?", (name,)
                ).fetchall()
                assert len(rows) == 1, f"Expected exactly one tracking row for {name}"
                assert float(rows[0][0]) == pytest.approx(expected[name], rel=1e-9, abs=1e-9)
        finally:
            conn.close()
    finally:
        with open(RUN_INFERENCE, "wb") as f:
            f.write(original_inference)
        os.chmod(RUN_INFERENCE, original_mode)
        for path in (saved_path, marker):
            if os.path.exists(path):
                os.remove(path)
        for name in names:
            for path in (
                os.path.join(source_root, name),
                os.path.join("/home/user/organized_data/positive", name),
                os.path.join("/home/user/organized_data/negative", name),
            ):
                if os.path.isdir(path):
                    shutil.rmtree(path)
        if os.path.isfile(DB_PATH):
            conn = sqlite3.connect(DB_PATH)
            try:
                conn.executemany("DELETE FROM results WHERE experiment_name = ?", [(n,) for n in names])
                conn.commit()
            finally:
                conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
