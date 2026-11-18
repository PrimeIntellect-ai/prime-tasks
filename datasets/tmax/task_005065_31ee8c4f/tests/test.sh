#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest

PROJECT = Path("/home/user/build_tools/impact_analyzer")
REPORT = Path("/home/user/report.log")
HARNESS = Path("/home/user/test_harness.sh")
ADDRESS = "127.0.0.1:50051"
METHOD = "impact.ImpactService/CalculateImpact"


def rust_env():
    env = os.environ.copy()
    env.update({
        "HOME": "/home/user",
        "USER": "user",
        "CARGO_HOME": "/home/user/.cargo",
        "RUSTUP_HOME": "/home/user/.rustup",
        "PATH": "/home/user/.cargo/bin:" + env.get("PATH", ""),
    })
    return env


def calculate_expected_score(v1, v2):
    file1 = f"/home/user/protos/{v1}/api.proto"
    file2 = f"/home/user/protos/{v2}/api.proto"

    assert os.path.isfile(file1), f"Expected proto file {file1} is missing."
    assert os.path.isfile(file2), f"Expected proto file {file2} is missing."

    result = subprocess.run(
        ["diff", "-U0", file1, file2],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode in (0, 1), f"diff command failed: {result.stderr}"

    added = 0
    deleted = 0
    for line in result.stdout.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            added += 1
        elif line.startswith("-") and not line.startswith("---"):
            deleted += 1
    return (deleted * deleted * 3) + added


def parse_json_objects(content):
    objects = []
    decoder = json.JSONDecoder()
    idx = 0
    while idx < len(content):
        while idx < len(content) and content[idx].isspace():
            idx += 1
        if idx >= len(content):
            break
        try:
            obj, consumed = decoder.raw_decode(content[idx:])
            objects.append(obj)
            idx += consumed
        except json.JSONDecodeError:
            next_brace = content.find("{", idx + 1)
            if next_brace == -1:
                break
            idx = next_brace
    return objects


def kill_port_50051():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "C383" and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc_dir in Path("/proc").glob("[0-9]*"):
        try:
            pid = int(proc_dir.name)
            if pid == os.getpid():
                continue
            for fd in (proc_dir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(pid)
                    break
        except (OSError, ValueError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(1)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(proc, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("The Rust gRPC server exited before becoming ready")
        try:
            with socket.create_connection(("127.0.0.1", 50051), timeout=1):
                return
        except OSError:
            time.sleep(0.25)
    pytest.fail("The Rust gRPC server did not listen on 127.0.0.1:50051")


def grpc_call(v1, v2, expect_success=True):
    result = subprocess.run(
        [
            "grpcurl", "-plaintext", "-d", json.dumps({"v1": v1, "v2": v2}),
            ADDRESS, METHOD,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    if expect_success:
        assert result.returncode == 0, f"grpcurl failed: {result.stderr}\n{result.stdout}"
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            pytest.fail(f"grpcurl returned invalid JSON: {result.stdout!r}: {exc}")
    assert result.returncode != 0, "Expected the gRPC request to fail"
    return result.stdout + result.stderr


def test_rust_project_exists():
    cargo_toml = PROJECT / "Cargo.toml"
    main_rs = PROJECT / "src/main.rs"
    assert cargo_toml.is_file(), f"Rust project manifest missing at {cargo_toml}"
    assert main_rs.is_file(), f"Rust project source missing at {main_rs}"


def test_harness_script_exists_and_executable():
    assert HARNESS.is_file(), f"Test harness script missing at {HARNESS}"
    assert os.access(HARNESS, os.X_OK), f"Test harness script {HARNESS} is not executable"


def test_harness_runs_and_report_contains_correct_scores():
    versions = ["1.0.0", "1.1.0", "2.0.0"]
    paths = [Path(f"/home/user/protos/{v}/api.proto") for v in versions]
    originals = [p.read_bytes() for p in paths]
    nonce = random.SystemRandom().randrange(10**8, 10**9)
    replacements = [
        f'''syntax = "proto3";\npackage api;\n// {nonce}\nmessage Alpha {{ string a = 1; }}\nmessage Shared {{ string value = 1; }}\n''',
        f'''syntax = "proto3";\npackage api;\n// {nonce + 1}\nmessage Alpha {{ string a = 1; string b = 2; }}\nmessage Shared {{ string value = 1; }}\nmessage Added {{ bool enabled = 1; }}\n''',
        f'''syntax = "proto3";\npackage api;\n// {nonce + 2}\nmessage Replacement {{ int64 id = 1; }}\nmessage Shared {{ string value = 1; string extra = 2; }}\nservice NewApi {{ rpc Fetch (Replacement) returns (Shared); }}\n''',
    ]

    kill_port_50051()
    try:
        for path, content in zip(paths, replacements):
            path.write_text(content)
        expected_score_1 = calculate_expected_score("1.0.0", "1.1.0")
        expected_score_2 = calculate_expected_score("1.1.0", "2.0.0")

        if REPORT.exists():
            REPORT.unlink()
        result = subprocess.run(
            [str(HARNESS)],
            cwd="/home/user",
            env=rust_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=420,
        )
        assert result.returncode == 0, f"test_harness.sh failed:\n{result.stdout}\n{result.stderr}"
        assert REPORT.is_file(), f"Report log missing at {REPORT}. Did the test harness run successfully?"

        content = REPORT.read_text().strip()
        assert content, f"{REPORT} is empty."
        json_objects = parse_json_objects(content)
        assert len(json_objects) >= 2, f"Could not find at least two JSON objects in {REPORT}. Content: {content}"
        scores = [obj.get("score") for obj in json_objects if isinstance(obj, dict) and "score" in obj]
        assert len(scores) >= 2, f"Could not find 'score' keys in the parsed JSON from {REPORT}."
        assert scores[0] == expected_score_1, f"First score in report.log is {scores[0]}, expected {expected_score_1}"
        assert scores[1] == expected_score_2, f"Second score in report.log is {scores[1]}, expected {expected_score_2}"
    finally:
        for path, content in zip(paths, originals):
            path.write_bytes(content)
        kill_port_50051()


def test_compiled_service_handles_derived_inputs_and_errors():
    env = rust_env()
    build = subprocess.run(
        ["cargo", "build", "--manifest-path", str(PROJECT / "Cargo.toml")],
        cwd=str(PROJECT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=420,
    )
    assert build.returncode == 0, f"Rust project failed to compile:\n{build.stdout}\n{build.stderr}"

    rng = random.SystemRandom()
    major = rng.randrange(700000, 900000)
    versions = [f"{major}.0.0", f"{major}.1.0", f"{major}.2.0"]
    roots = [Path("/home/user/protos") / version for version in versions]
    token = rng.randrange(10**10, 10**11)
    contents = [
        f'''syntax = "proto3";\npackage dynamic;\n// token {token}\nmessage One {{ string a = 1; }}\nmessage Keep {{ int32 x = 1; }}\n''',
        f'''syntax = "proto3";\npackage dynamic;\n// token {token + 1}\nmessage One {{ string a = 1; string b = 2; }}\nmessage Keep {{ int32 x = 1; }}\nmessage Two {{ bool ok = 1; }}\n''',
        f'''syntax = "proto3";\npackage dynamic;\n// token {token + 2}\nmessage Three {{ bytes payload = 1; }}\nmessage Keep {{ int32 x = 1; int32 y = 2; }}\nservice Dynamic {{ rpc Go (Three) returns (Keep); }}\n''',
    ]

    proc = None
    kill_port_50051()
    try:
        for root, content in zip(roots, contents):
            root.mkdir(parents=True, exist_ok=False)
            (root / "api.proto").write_text(content)

        expected_01 = calculate_expected_score(versions[0], versions[1])
        expected_12 = calculate_expected_score(versions[1], versions[2])

        proc = subprocess.Popen(
            ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT / "Cargo.toml")],
            cwd=str(PROJECT),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        wait_for_port(proc)

        response_01 = grpc_call(versions[0], versions[1])
        response_12 = grpc_call(versions[1], versions[2])
        assert response_01.get("score") == expected_01, f"Dynamic score was {response_01.get('score')}, expected {expected_01}"
        assert response_12.get("score") == expected_12, f"Dynamic score was {response_12.get('score')}, expected {expected_12}"

        invalid = grpc_call(versions[1], versions[0], expect_success=False).lower()
        assert "invalidargument" in invalid, f"Reverse versions did not return InvalidArgument: {invalid}"

        equal = grpc_call(versions[1], versions[1], expect_success=False).lower()
        assert "invalidargument" in equal, f"Equal versions did not return InvalidArgument: {equal}"

        missing_version = f"{major}.9.0"
        missing = grpc_call(versions[2], missing_version, expect_success=False).lower()
        assert "notfound" in missing, f"Missing proto did not return NotFound: {missing}"
    finally:
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        kill_port_50051()
        for root in roots:
            shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
