#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pwd
import random
import re
import shutil
import stat
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

TOLERANCE_MSE = 1e-5


def compute_ground_truth(file_path):
    edges = []
    with open(file_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                edges.append((int(parts[0]), int(parts[1])))

    if not edges:
        return [0.0] * 5

    max_node = max(max(u, v) for u, v in edges)
    n = max_node + 1
    A = np.zeros((n, n), dtype=float)
    for u, v in edges:
        A[u, v] = 1.0
        A[v, u] = 1.0

    s = np.linalg.svd(A, compute_uv=False)
    s = np.sort(s)[::-1]

    features = list(s[:5])
    while len(features) < 5:
        features.append(0.0)

    return features


def test_embeddings_csv_exists():
    agent_csv = "/home/user/embeddings.csv"
    assert os.path.exists(agent_csv), f"Output file {agent_csv} does not exist."
    assert os.path.isfile(agent_csv), f"{agent_csv} is not a file."


def test_embeddings_mse():
    dataset_dir = "/app/dataset"
    agent_csv = "/home/user/embeddings.csv"

    assert os.path.exists(agent_csv), f"Output file {agent_csv} missing."

    try:
        agent_df = pd.read_csv(agent_csv).set_index('filename')
    except Exception as e:
        pytest.fail(f"Could not read {agent_csv} as a CSV file: {e}")

    mse_list = []

    files = [f for f in os.listdir(dataset_dir) if f.endswith('.txt')]
    assert len(files) > 0, "Dataset directory is empty or missing .txt files."

    for filename in files:
        true_features = compute_ground_truth(os.path.join(dataset_dir, filename))

        assert filename in agent_df.index, f"{filename} missing from CSV."

        try:
            agent_features = agent_df.loc[filename, ['f1', 'f2', 'f3', 'f4', 'f5']].values.astype(float)
        except KeyError as e:
            pytest.fail(f"Missing expected columns in CSV for {filename}: {e}")

        mse = np.mean((np.array(true_features) - agent_features)**2)
        mse_list.append(mse)

    total_mse = np.mean(mse_list)

    assert total_mse <= TOLERANCE_MSE, f"MSE {total_mse} exceeds threshold {TOLERANCE_MSE}"


def _drop_to_user():
    account = pwd.getpwnam("user")
    os.initgroups(account.pw_name, account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def _strip_rust_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//.*', '', text)


def _validate_generated_csv(csv_path, expected):
    try:
        frame = pd.read_csv(csv_path)
    except Exception as exc:
        return False, f"could not read output CSV: {exc}"

    required = ['filename', 'f1', 'f2', 'f3', 'f4', 'f5']
    if not all(column in frame.columns for column in required):
        return False, f"missing required columns; found {list(frame.columns)}"
    if frame['filename'].duplicated().any():
        return False, "output contains duplicate filenames"

    frame = frame.set_index('filename')
    if set(frame.index) != set(expected):
        return False, "output filenames do not match the novel input files"

    errors = []
    try:
        for filename, truth in expected.items():
            values = frame.loc[filename, ['f1', 'f2', 'f3', 'f4', 'f5']].to_numpy(dtype=float)
            if values.shape != (5,) or not np.all(np.isfinite(values)):
                return False, f"invalid feature values for {filename}"
            errors.extend((values - np.asarray(truth, dtype=float)) ** 2)
    except Exception as exc:
        return False, f"invalid feature data: {exc}"

    mse = float(np.mean(errors))
    if mse > TOLERANCE_MSE:
        return False, f"novel-input MSE {mse} exceeds {TOLERANCE_MSE}"
    return True, "ok"


def test_rust_extractor_builds_and_handles_novel_inputs():
    project = "/home/user/rust_extractor"
    cargo_toml = os.path.join(project, "Cargo.toml")
    assert os.path.isdir(project), f"Rust project {project} does not exist."
    assert os.path.isfile(cargo_toml), f"{cargo_toml} does not exist."

    rust_sources = glob.glob(os.path.join(project, "**", "*.rs"), recursive=True)
    assert rust_sources, "Rust project contains no .rs source files."

    source = "\n".join(_strip_rust_comments(open(path, encoding="utf-8", errors="ignore").read()) for path in rust_sources)
    delegation_patterns = [
        r'\bstd\s*::\s*process\b',
        r'\bCommand\s*::\s*new\b',
        r'oracle_extractor',
        r'\bpython(?:3)?\b',
        r'\bexecve\b',
        r'\blibc\s*::\s*system\b',
    ]
    for pattern in delegation_patterns:
        assert not re.search(pattern, source, flags=re.I), "Rust extractor delegates computation to an external program instead of implementing it."

    for path in rust_sources:
        os.utime(path, None)

    build_env = os.environ.copy()
    build_env["HOME"] = "/home/user"
    build = subprocess.run(
        ["cargo", "build", "--message-format=json"],
        cwd=project,
        env=build_env,
        preexec_fn=_drop_to_user,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    assert build.returncode == 0, f"Rust project failed to build:\n{build.stderr[-4000:]}"

    executables = []
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
            executable = message.get("executable")
            if executable and os.path.isfile(executable):
                executables.append(executable)
    executables = list(dict.fromkeys(executables))
    assert executables, "Cargo build did not produce a Rust binary target."

    work = tempfile.mkdtemp(prefix="rust_extractor_verify_", dir="/tmp")
    os.chmod(work, 0o777)
    input_dir = os.path.join(work, "novel_graphs")
    os.mkdir(input_dir, 0o755)

    rng = random.SystemRandom()
    filenames = ["case_02.txt", "case_1.txt", "molecule_alpha.txt", "zeta.txt"]
    filenames += [f"random_{i:02d}_{rng.randrange(1 << 30):08x}.txt" for i in range(10)]

    for index, filename in enumerate(filenames):
        n = [3, 4, 7, 11, 16, 21][index % 6]
        edges = set()
        for node in range(1, n):
            parent = rng.randrange(node)
            edges.add((min(node, parent), max(node, parent)))
        target = min(n * 2 + index % 4, n * (n - 1) // 2)
        while len(edges) < target:
            u, v = rng.randrange(n), rng.randrange(n)
            if u != v:
                edges.add((min(u, v), max(u, v)))
        with open(os.path.join(input_dir, filename), "w") as handle:
            for u, v in sorted(edges):
                handle.write(f"{u} {v}\n")

    expected = {
        filename: compute_ground_truth(os.path.join(input_dir, filename))
        for filename in filenames
    }

    oracle = "/app/oracle_extractor"
    oracle_mode = stat.S_IMODE(os.stat(oracle).st_mode) if os.path.exists(oracle) else None
    failures = []
    succeeded = False
    try:
        if oracle_mode is not None:
            os.chmod(oracle, 0)

        runtime_env = {"HOME": "/home/user", "PATH": "/nonexistent", "RUST_BACKTRACE": "0"}
        for number, executable in enumerate(executables):
            output_csv = os.path.join(work, f"novel_output_{number}.csv")
            try:
                run = subprocess.run(
                    [executable, input_dir, output_csv],
                    cwd=project,
                    env=runtime_env,
                    preexec_fn=_drop_to_user,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=60,
                )
            except Exception as exc:
                failures.append(f"{executable}: execution failed: {exc}")
                continue

            if run.returncode != 0:
                failures.append(f"{executable}: exited {run.returncode}: {run.stderr[-1000:]}")
                continue
            if not os.path.isfile(output_csv):
                failures.append(f"{executable}: did not create the requested CSV file")
                continue

            valid, detail = _validate_generated_csv(output_csv, expected)
            if valid:
                succeeded = True
                break
            failures.append(f"{executable}: {detail}")
    finally:
        if oracle_mode is not None:
            os.chmod(oracle, oracle_mode)
        shutil.rmtree(work, ignore_errors=True)

    assert succeeded, "No Rust binary correctly processed novel inputs. " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
