#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import random
import subprocess
import time

from elftools.elf.elffile import ELFFile

BASE = "/home/user/artifact_manager"


def expected_elf_output(path):
    with open(path, "rb") as f:
        elf = ELFFile(f)
        machine = elf.header["e_machine"]
        entry = hex(elf.header["e_entry"])
        text = elf.get_section_by_name(".text")
        size = text["sh_size"] if text is not None else 0
        return f"{machine}|{entry}|{size}"


def redis_cmd(*args):
    return subprocess.run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", *args],
        capture_output=True, text=True, timeout=5
    )


def test_config_updated():
    config_path = f"{BASE}/config.ini"
    assert os.path.isfile(config_path), f"Missing {config_path}"

    config = configparser.ConfigParser()
    config.read(config_path)

    with open(config_path, "r") as f:
        content = f.read()

    assert "queue_type = redis" in content or "queue_type=redis" in content.replace(" ", ""), \
        "config.ini does not have 'queue_type = redis'"
    assert "redis://127.0.0.1:6379/0" in content, \
        "config.ini does not have the correct redis_url"


def test_fuzz_equivalence_elf_parser():
    agent_parser = f"{BASE}/elf_parser.py"
    assert os.path.isfile(agent_parser), f"Agent parser missing at {agent_parser}"
    assert os.access(agent_parser, os.X_OK), f"Agent parser {agent_parser} is not executable"

    elf_candidates = []
    for d in ["/usr/bin", "/usr/lib"]:
        for root, _, files in os.walk(d):
            for name in files:
                path = os.path.join(root, name)
                if os.path.isfile(path) and not os.path.islink(path):
                    try:
                        with open(path, "rb") as f:
                            if f.read(4) == b"\x7fELF":
                                elf_candidates.append(path)
                    except OSError:
                        pass

    random.seed(42)
    test_files = random.sample(elf_candidates, min(50, len(elf_candidates)))
    assert test_files, "No ELF files found for testing"

    for elf_file in test_files:
        proc = subprocess.run(
            [agent_parser, elf_file], capture_output=True, text=True, timeout=10
        )
        assert proc.returncode == 0, f"Parser failed on {elf_file}: {proc.stderr}"
        assert proc.stdout == expected_elf_output(elf_file) + "\n", \
            f"Output mismatch on {elf_file}. Expected {expected_elf_output(elf_file)!r}, got {proc.stdout!r}"
        assert proc.stderr == "", f"Parser wrote to stderr on {elf_file}: {proc.stderr!r}"


def test_end_to_end_upload_and_symlink():
    test_elf = "/usr/bin/ls"
    assert os.path.isfile(test_elf), f"Test file {test_elf} missing"
    arch = expected_elf_output(test_elf).split("|", 1)[0]

    nonce = f"verifier_{os.getpid()}_{time.time_ns()}"
    upload_name = nonce + "_ls"
    expected_upload = f"{BASE}/uploads/{upload_name}"
    expected_symlink = f"{BASE}/curated/{arch}/{upload_name}"
    assert not os.path.lexists(expected_upload)
    assert not os.path.lexists(expected_symlink)

    # The instructed launcher must bring up Redis, Flask, and the worker.
    subprocess.run([f"{BASE}/start_services.sh"], check=True, timeout=15)

    deadline = time.time() + 15
    while time.time() < deadline:
        ping = redis_cmd("PING")
        if ping.returncode == 0 and ping.stdout.strip() == "PONG":
            break
        time.sleep(0.25)
    else:
        raise AssertionError("Redis did not start")

    redis_cmd("DEL", "upload_queue")

    response_file = f"/tmp/{nonce}.response"
    curl = subprocess.run(
        ["curl", "-sS", "--fail", "--max-time", "10", "-o", response_file,
         "-w", "%{http_code}", "-F", f"file=@{test_elf};filename={upload_name}",
         "http://127.0.0.1:5000/upload"],
        capture_output=True, text=True, timeout=15
    )
    assert curl.returncode == 0, f"Upload failed: {curl.stderr}"
    assert curl.stdout.strip() == "200", f"Unexpected HTTP status: {curl.stdout!r}"
    with open(response_file) as f:
        assert f.read() == "File uploaded successfully"
    assert os.path.isfile(expected_upload), "Flask did not save the uploaded file"

    # Observe that this fresh request was actually enqueued before allowing the worker to consume it.
    observed_queue = False
    deadline = time.time() + 10
    while time.time() < deadline:
        queued = redis_cmd("LRANGE", "upload_queue", "0", "-1")
        assert queued.returncode == 0, queued.stderr
        if expected_upload in queued.stdout.splitlines():
            observed_queue = True
            break
        if os.path.islink(expected_symlink):
            # A fast worker may consume immediately; Redis command statistics still prove queue use.
            info = redis_cmd("INFO", "commandstats")
            assert info.returncode == 0, info.stderr
            if "cmdstat_lpush" in info.stdout and "cmdstat_brpop" in info.stdout:
                observed_queue = True
                break
        time.sleep(0.1)
    assert observed_queue, "Fresh upload was not passed through the Redis upload_queue"

    deadline = time.time() + 15
    while time.time() < deadline and not os.path.islink(expected_symlink):
        time.sleep(0.2)
    assert os.path.islink(expected_symlink), f"Expected symlink {expected_symlink} was not created"
    assert os.path.realpath(expected_symlink) == os.path.realpath(expected_upload), \
        f"Symlink does not target the fresh uploaded file: {os.readlink(expected_symlink)}"

    queue = redis_cmd("LRANGE", "upload_queue", "0", "-1")
    assert queue.returncode == 0, queue.stderr
    assert expected_upload not in queue.stdout.splitlines(), "Worker did not pop the event from Redis"

    with open(f"{BASE}/logs/upload.log", errors="replace") as f:
        assert expected_upload in f.read(), "Fresh upload was not recorded in the upload log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
