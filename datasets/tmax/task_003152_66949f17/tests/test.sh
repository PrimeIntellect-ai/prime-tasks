#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/simulate"
_SERVER_PROCESS = None
_BUILD_DIR = None


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    if state != "0A":
                        continue
                    if table.endswith("tcp") and local == "0100007F:1F90":
                        inodes.add(inode)
                    elif table.endswith("tcp6") and local.endswith("0100007F:1F90"):
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    result = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(proc + "/fd"):
                try:
                    target = os.readlink(proc + "/fd/" + fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(pid)
        except (FileNotFoundError, PermissionError):
            continue
    return result


def cargo_candidates(initial_pids):
    found = []

    def add_ancestors(path):
        try:
            p = Path(path).resolve()
        except OSError:
            return
        if p.is_file():
            p = p.parent
        for parent in (p, *p.parents):
            manifest = parent / "Cargo.toml"
            if manifest.is_file() and manifest not in found:
                found.append(manifest)

    for pid in initial_pids:
        try:
            add_ancestors(os.readlink(f"/proc/{pid}/cwd"))
        except OSError:
            pass
        try:
            add_ancestors(os.readlink(f"/proc/{pid}/exe"))
        except OSError:
            pass

    for pattern in (
        "/home/user/**/Cargo.toml",
        "/app/**/Cargo.toml",
        "/root/**/Cargo.toml",
        "/workspace/**/Cargo.toml",
        "/tmp/**/Cargo.toml",
    ):
        for name in glob.glob(pattern, recursive=True):
            p = Path(name)
            if "/target/" not in str(p) and p not in found:
                found.append(p)
    return found


def stop_listener(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(), "Could not stop the pre-existing listener for clean Rust rebuild testing"


def build_rust_server(manifests):
    cargo = "/opt/rust/cargo/bin/cargo"
    assert os.path.isfile(cargo), "Cargo is unavailable"
    failures = []
    for index, manifest in enumerate(manifests[:12]):
        project = manifest.parent
        assert any(project.rglob("*.rs")), f"Cargo project {project} has no Rust source files"
        build_dir = f"/tmp/verifier-rust-build-{index}"
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = build_dir
        try:
            result = subprocess.run(
                [cargo, "build", "--release", "--message-format=json"],
                cwd=project,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=240,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{manifest}: build timed out")
            continue
        if result.returncode != 0:
            failures.append(f"{manifest}: {result.stderr[-1000:]}")
            continue

        executables = []
        for line in result.stdout.splitlines():
            try:
                message = json.loads(line)
            except ValueError:
                continue
            executable = message.get("executable")
            target = message.get("target", {})
            if executable and "bin" in target.get("kind", []):
                executables.append(executable)
        if executables:
            return project, build_dir, list(dict.fromkeys(executables))
        failures.append(f"{manifest}: release build produced no executable binary")
    pytest.fail("No usable Rust HTTP server project could be built. " + " | ".join(failures))


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_start_rust_server():
    global _SERVER_PROCESS, _BUILD_DIR
    initial = listener_pids()
    manifests = cargo_candidates(initial)
    assert manifests, "No Cargo.toml for the required Rust server was found"

    project, build_dir, executables = build_rust_server(manifests)
    stop_listener(initial)

    for executable in executables:
        with open(executable, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Built server {executable} is not an ELF executable"
        proc = subprocess.Popen(
            [executable],
            cwd=project,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.time() + 8
        while time.time() < deadline and proc.poll() is None and not listener_pids():
            time.sleep(0.05)
        owners = listener_pids()
        if proc.poll() is None and owners:
            owner_exes = []
            for pid in owners:
                try:
                    owner_exes.append(os.path.realpath(f"/proc/{pid}/exe"))
                except OSError:
                    pass
            expected = os.path.realpath(executable)
            if expected in owner_exes and expected.startswith(os.path.realpath(build_dir) + os.sep):
                _SERVER_PROCESS = proc
                _BUILD_DIR = build_dir
                return
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stop_listener(listener_pids())

    pytest.fail("Freshly compiled Rust binaries did not provide the required 127.0.0.1:8080 listener")


def parse_mean(response):
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "mean_sq_dist" in data, f"'mean_sq_dist' missing from response: {data}"
    value = data["mean_sq_dist"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool), (
        f"'mean_sq_dist' should be a number, got {type(value)}"
    )
    assert math.isfinite(value), f"'mean_sq_dist' must be finite, got {value}"
    return float(value)


def post_simulation(path, iterations, timeout=15):
    try:
        response = requests.post(
            URL, json={"fasta_path": str(path), "iterations": iterations}, timeout=timeout
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")
    return parse_mean(response)


def test_fasta_file_exists():
    """Ensure the target FASTA file exists and contains the correct sequence."""
    fasta_path = "/home/user/target.fasta"
    assert os.path.isfile(fasta_path), f"FASTA file is missing at {fasta_path}"

    with open(fasta_path, "r") as f:
        lines = f.readlines()

    sequence = "".join(line.strip() for line in lines if not line.startswith(">"))
    assert "ACDFG" in sequence, f"Expected sequence 'ACDFG' not found in {fasta_path}. Found: {sequence}"

    nonempty = [line.strip() for line in lines if line.strip()]
    assert nonempty and nonempty[0].startswith(">") and len(nonempty[0]) > 1, "FASTA must begin with a nonempty header"
    assert all(not line.startswith(">") for line in nonempty[1:]), "Target FASTA must contain exactly one record"
    assert sequence == "ACDFG", f"Expected the complete dictated sequence ACDFG, found {sequence!r}"
    assert all(set(line) <= set("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for line in nonempty[1:]), "Invalid FASTA sequence content"


def test_simulation_endpoint_target_fasta():
    mean_sq_dist = post_simulation("/home/user/target.fasta", 500000)
    assert 54.5 <= mean_sq_dist <= 55.5, (
        f"Expected mean_sq_dist to be between 54.5 and 55.5, got {mean_sq_dist}"
    )


def test_simulation_endpoint_adversarial_fasta(tmp_path):
    fasta_path = tmp_path / "test.fasta"
    fasta_path.write_text(">Adversarial\nAAACCC\n")
    mean_sq_dist = post_simulation(fasta_path, 500000)
    assert 14.5 <= mean_sq_dist <= 15.5, (
        f"Expected mean_sq_dist to be between 14.5 and 15.5, got {mean_sq_dist}"
    )


def test_randomized_sequences_against_derived_expectations(tmp_path):
    rng = secrets.SystemRandom()
    lengths = {"A": 1.0, "C": 2.0, "D": 3.0, "F": 4.0, "G": 5.0}
    alphabet = "ACDFGMEKLPQX"

    for case in range(5):
        sequence = "".join(rng.choice(alphabet) for _ in range(rng.randint(7, 24)))
        if not any(ch in lengths for ch in sequence):
            sequence += rng.choice(tuple(lengths))
        path = tmp_path / f"{secrets.token_hex(10)}.fasta"
        split = rng.randint(1, len(sequence) - 1)
        path.write_text(f">{secrets.token_hex(6)}\n{sequence[:split]}\n{sequence[split:]}\n")

        squared = [lengths.get(ch, 0.0) ** 2 for ch in sequence]
        expected = sum(squared)
        variance_one_walk = (2.0 / 3.0) * (expected ** 2 - sum(x * x for x in squared))
        iterations = 80000 + rng.randrange(0, 20001)
        tolerance = max(0.18, 7.0 * math.sqrt(max(0.0, variance_one_walk) / iterations))
        observed = post_simulation(path, iterations, timeout=25)
        assert abs(observed - expected) <= tolerance, (
            f"For hidden sequence {sequence}, expected {expected} within {tolerance}, got {observed}"
        )


def test_single_walks_are_random_uniform_3d_directions(tmp_path):
    rng = secrets.SystemRandom()
    lengths = {"A": 1.0, "C": 2.0, "D": 3.0, "F": 4.0, "G": 5.0}
    first, second = rng.sample(list(lengths), 2)
    a, b = lengths[first], lengths[second]
    path = tmp_path / f"walk-{secrets.token_hex(10)}.fasta"
    path.write_text(f">random-pair\n{first}{second}\n")

    cosines = []
    for _ in range(60):
        distance_sq = post_simulation(path, 1)
        cosine = (distance_sq - a * a - b * b) / (2.0 * a * b)
        assert -1.000001 <= cosine <= 1.000001, (
            f"A one-iteration two-step walk returned impossible squared distance {distance_sq}"
        )
        cosines.append(cosine)

    assert len({round(x, 7) for x in cosines}) >= 20, "Single-walk results are fixed rather than Monte Carlo samples"
    sample_mean = sum(cosines) / len(cosines)
    sample_second_moment = sum(x * x for x in cosines) / len(cosines)
    assert abs(sample_mean) < 0.28, f"3D direction dot products are biased: mean {sample_mean}"
    assert 0.18 < sample_second_moment < 0.52, (
        f"Directions are not consistent with uniform sampling on a 3D sphere: E[cos^2]={sample_second_moment}"
    )
    assert min(cosines) < -0.45 and max(cosines) > 0.45, "Random directions do not cover the sphere"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
