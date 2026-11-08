#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from collections import Counter

import pytest


def test_timeline_log():
    timeline_path = "/home/user/timeline.log"
    assert os.path.isfile(timeline_path), f"{timeline_path} does not exist."

    with open(timeline_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 8, f"Expected 8 lines in {timeline_path}, but found {len(lines)}."

    timestamps = [line.split(" ")[0] for line in lines]
    assert timestamps == sorted(timestamps), "Lines in timeline.log are not sorted chronologically."

    source_paths = [
        "/home/user/logs/service_a.log",
        "/home/user/logs/service_b.log",
        "/home/user/logs/state-sync.log",
    ]
    source_lines = []
    for path in source_paths:
        with open(path, "r") as f:
            source_lines.extend(line.strip() for line in f if line.strip())

    assert Counter(lines) == Counter(source_lines), (
        "timeline.log must contain exactly all lines from service_a.log, "
        "service_b.log, and state-sync.log."
    )


def test_bad_file_txt():
    bad_file_path = "/home/user/bad_file.txt"
    assert os.path.isfile(bad_file_path), f"{bad_file_path} does not exist."

    with open(bad_file_path, "r") as f:
        content = f.read().strip()

    assert content == "/var/data/critical data.txt", f"Expected bad_file.txt to contain '/var/data/critical data.txt', but got '{content}'."


def run_binary(binary_path, state_file):
    try:
        return subprocess.run(
            [binary_path, state_file],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Rust binary timed out. It might still be stuck in an infinite loop.")


def test_rust_binary_execution():
    project_path = "/home/user/state-sync"
    binary_path = "/home/user/state-sync/target/release/state-sync"
    state_file = "/home/user/logs/state.txt"

    assert os.path.isfile(binary_path), f"Rust binary {binary_path} does not exist. Did you run 'cargo build --release'?"
    assert os.access(binary_path, os.X_OK), f"Rust binary {binary_path} is not executable."
    assert os.path.isfile(os.path.join(project_path, "src/main.rs")), "src/main.rs does not exist."

    subprocess.run(
        ["/usr/bin/cargo", "clean"],
        cwd=project_path,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    build = subprocess.run(
        ["/usr/bin/cargo", "build", "--release"],
        cwd=project_path,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(binary_path), "cargo build did not produce the expected state-sync binary."
    assert os.access(binary_path, os.X_OK), f"Rust binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The produced state-sync artifact is not a compiled native binary."

    result = run_binary(binary_path, state_file)
    assert result.returncode == 0, f"Expected exit code 0, but got {result.returncode}. Stderr: {result.stderr}"
    assert "Convergence achieved." in result.stdout, "The output did not contain 'Convergence achieved.'"

    token = secrets.token_hex(12)
    paths = [
        f"/var/data/{token} quarterly report.txt",
        f"/srv/archive/{token} two spaces here.bin",
        f"/tmp/{token}.json",
        f"/opt/shared/{token} final copy.tar.gz",
    ]
    services = ["service_a", "service_b", "state-sync", "service_c"]
    statuses = ["OK", "PENDING", "FAILED", "SYNCED"]
    generated_file = f"/tmp/state-sync-verifier-{token}.txt"
    with open(generated_file, "w") as f:
        for index, (service, path, status) in enumerate(zip(services, paths, statuses), start=1):
            f.write(f"2042-07-19T12:34:{index:02d}Z {service} \"{path}\" {status}\n")

    generated_result = run_binary(binary_path, generated_file)
    assert generated_result.returncode == 0, (
        f"Binary failed on valid quoted paths. Stderr: {generated_result.stderr}"
    )
    output_lines = [line.strip() for line in generated_result.stdout.splitlines() if line.strip()]
    expected_lines = [f"Synced: {path}" for path in paths] + ["Convergence achieved."]
    assert output_lines == expected_lines, (
        "The parser did not extract the four fields and quoted file paths correctly. "
        f"Expected {expected_lines!r}, got {output_lines!r}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
