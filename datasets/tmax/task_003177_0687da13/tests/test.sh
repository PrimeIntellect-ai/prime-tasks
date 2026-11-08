#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def assert_elf(path):
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected an ELF executable at {path}"


def listener_pids(port):
    socket_inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[-1].upper() == wanted_port and state == "0A":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def post_count(count, timeout=10):
    payload = json.dumps({"count": count}).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:8082/process_batch",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            body = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        raise AssertionError(f"Failed to connect to the processor on port 8082: {exc}")
    return status, body, time.monotonic() - start


def test_backup_files_exist_and_are_real_backups():
    backup_binary = "/home/user/backup/metrics_processor"
    backup_db = "/home/user/backup/metrics.db"
    current_binary = "/app/rust_processor/target/release/metrics_processor"

    assert os.path.isfile(backup_binary), f"Backup binary missing at {backup_binary}"
    assert os.path.isfile(backup_db), f"Backup DB missing at {backup_db}"
    assert_elf(backup_binary)
    assert os.stat(backup_binary).st_mode & stat.S_IXUSR, "Backup binary is not executable"
    assert os.path.getsize(backup_db) == 0, "The original metrics.db backup should be empty"

    assert_elf(current_binary)
    assert sha256_file(backup_binary) != sha256_file(current_binary), (
        "Backup binary is identical to the optimized binary; the pre-change binary was not preserved"
    )


def test_rust_source_is_optimized_and_builds_in_release_mode():
    source_path = "/app/rust_processor/src/main.rs"
    assert os.path.isfile(source_path), f"Rust source missing at {source_path}"
    source = open(source_path, encoding="utf-8").read()

    assert not re.search(r"\.insert\s*\(\s*0\s*,", source), (
        "The O(N^2) front-insertion bottleneck is still present"
    )
    assert re.search(r"\bpush(?:_front|_back)?\s*\(|\.collect\s*(?:::[^()]*)?\(", source), (
        "No linear-time push/iterator collection strategy was found"
    )

    build_dir = tempfile.mkdtemp(prefix="verifier-rust-target-")
    try:
        result = subprocess.run(
            ["cargo", "build", "--release", "--target-dir", build_dir],
            cwd="/app/rust_processor",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=240,
        )
        assert result.returncode == 0, f"Rust release build failed:\n{result.stdout}"
        assert_elf(os.path.join(build_dir, "release", "metrics_processor"))
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_deploy_expect_script_exists_and_drives_all_stages():
    expect_script = "/home/user/deploy.exp"
    manager = "/app/deploy_manager.py"
    assert os.path.isfile(expect_script), f"Expect script missing at {expect_script}"

    nonce = uuid.uuid4().hex
    marker = f"/tmp/deploy-verifier-{nonce}"
    backup_manager = f"/tmp/deploy-manager-{nonce}.bak"
    shutil.copy2(manager, backup_manager)

    challenge = '''import os, sys
if sys.argv[1:] != ["--binary", "/app/rust_processor/target/release/metrics_processor"]:
    sys.exit(20)
prompts = [
    "Deploy to stage 1 (10%)? [y/N]: ",
    "Deploy to stage 2 (50%)? [y/N]: ",
    "Deploy to stage 3 (100%)? [y/N]: ",
    "Commit rollout? [y/N]: ",
]
for prompt in prompts:
    if input(prompt).strip().lower() != "y":
        sys.exit(21)
with open(os.environ["DEPLOY_VERIFY_MARKER"], "w") as f:
    f.write("all-stages-confirmed")
print("Deployment successful.")
'''
    try:
        with open(manager, "w", encoding="utf-8") as f:
            f.write(challenge)
        env = os.environ.copy()
        env["DEPLOY_VERIFY_MARKER"] = marker
        result = subprocess.run(
            ["expect", expect_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            timeout=20,
        )
        assert result.returncode == 0, f"Expect deployment failed:\n{result.stdout}"
        assert os.path.isfile(marker), (
            "Expect script did not run deploy_manager.py with the required binary and answer y to all prompts"
        )
        assert open(marker, encoding="utf-8").read() == "all-stages-confirmed"
    finally:
        shutil.copy2(backup_manager, manager)
        os.unlink(backup_manager)
        if os.path.exists(marker):
            os.unlink(marker)


def test_deployed_processor_is_the_rebuilt_binary():
    binary = "/app/rust_processor/target/release/metrics_processor"
    expected_hash = sha256_file(binary)
    owners = listener_pids(8082)
    assert owners, "No process is listening on port 8082"

    matching = []
    for pid in owners:
        try:
            if sha256_file(f"/proc/{pid}/exe") == expected_hash:
                matching.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    assert matching, (
        "The process listening on port 8082 is not the rebuilt metrics_processor binary"
    )


def test_processor_outputs_and_latency_metric():
    # Preserve the original fixed benchmark and validate its derived response.
    status, body, latency = post_count(50000)
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert body == "Processed 50000", f"Incorrect processor output: {body!r}"
    assert latency <= 1.0, f"Latency {latency:.4f}s exceeds 1.0s threshold"

    # Exercise non-fixed inputs so a constant or immediate canned response cannot pass.
    counts = [0, 1, random.SystemRandom().randint(137, 9917), random.SystemRandom().randint(60000, 90000)]
    for count in counts:
        status, body, _ = post_count(count)
        assert status == 200, f"Expected HTTP 200 for count={count}, got {status}"
        assert body == f"Processed {count}", (
            f"Incorrect output for count={count}: expected 'Processed {count}', got {body!r}"
        )

    print(f"LATENCY_METRIC: {latency}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
