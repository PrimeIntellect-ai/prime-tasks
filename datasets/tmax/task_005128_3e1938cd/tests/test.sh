#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import posixpath
import random
import shutil
import subprocess
import tempfile
import uuid
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import pytest

SCRIPT_PATH = "/home/user/validate_mounts.py"
ACCEPTED_DIR = "/home/user/accepted_mounts"
REJECTED_LOG = "/home/user/rejected.log"


def test_vendored_package_fixed():
    file_path = "/app/vendored/fsmeta-utils/fsmeta/validators.py"
    assert os.path.isfile(file_path), f"Validators file {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read()

    buggy_line = "def validate_quota(size_bytes) return size_bytes > 0"
    assert buggy_line not in content, f"The deliberate syntax error was not fixed in {file_path}."

    result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "python3", "-c",
            "from fsmeta.validators import validate_quota; "
            "import importlib.metadata as m; "
            "assert m.version('fsmeta-utils') == '1.0.0'; "
            "assert validate_quota(1) is True; "
            "assert validate_quota(0) is False; "
            "assert validate_quota(-1) is False"
        ],
        cwd="/tmp",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "fsmeta-utils is not installed and working in the user environment: "
        f"{result.stderr}"
    )


def test_timezone_persistently_configured():
    env = os.environ.copy()
    env.pop("TZ", None)
    result = subprocess.run(
        ["su", "-", "user", "-c", "printf '%s' \"$TZ\""],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "Etc/UTC", (
        "The user login environment must persistently set TZ=Etc/UTC"
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def run_script(corpus_dir):
    env = os.environ.copy()
    env["TZ"] = "Etc/UTC"
    return subprocess.run(
        ["python3", SCRIPT_PATH, corpus_dir],
        capture_output=True,
        text=True,
        env=env,
    )


def setup_test_env():
    if os.path.exists(ACCEPTED_DIR):
        shutil.rmtree(ACCEPTED_DIR)
    if os.path.exists(REJECTED_LOG):
        os.remove(REJECTED_LOG)


def get_rejected_lines():
    if not os.path.exists(REJECTED_LOG):
        return []
    with open(REJECTED_LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def get_rejected_files():
    return set(get_rejected_lines())


def get_accepted_files():
    if not os.path.exists(ACCEPTED_DIR):
        return set()
    return set(os.listdir(ACCEPTED_DIR))


def assert_exact_outputs(corpus_dir, expected_accepted, expected_rejected):
    accepted = get_accepted_files()
    rejected_lines = get_rejected_lines()
    assert accepted == expected_accepted, (
        f"Accepted entries differ: expected {expected_accepted}, got {accepted}"
    )
    assert set(rejected_lines) == expected_rejected, (
        f"Rejected entries differ: expected {expected_rejected}, got {set(rejected_lines)}"
    )
    assert len(rejected_lines) == len(expected_rejected), (
        "Each rejected filename must be logged exactly once"
    )
    for name in expected_accepted:
        source = os.path.join(corpus_dir, name)
        copied = os.path.join(ACCEPTED_DIR, name)
        assert os.path.isfile(copied), f"Accepted output {copied} is not a file"
        with open(source, "rb") as src, open(copied, "rb") as dst:
            assert dst.read() == src.read(), f"Accepted file {name} was not copied exactly"


def test_clean_corpus():
    setup_test_env()
    corpus_dir = "/app/tests/corpora/clean"
    assert os.path.isdir(corpus_dir), f"Clean corpus directory {corpus_dir} missing."
    clean_files = {f for f in os.listdir(corpus_dir) if f.endswith(".json")}

    res = run_script(corpus_dir)
    assert res.returncode == 0, f"Script failed on clean corpus:\n{res.stderr}"

    accepted = get_accepted_files()
    rejected = get_rejected_files()
    missing_accepted = clean_files - accepted
    assert not missing_accepted, (
        f"{len(missing_accepted)} of {len(clean_files)} clean files were NOT accepted: "
        f"{missing_accepted}"
    )
    wrongly_rejected = clean_files.intersection(rejected)
    assert not wrongly_rejected, (
        f"{len(wrongly_rejected)} clean files were wrongly rejected: {wrongly_rejected}"
    )
    assert_exact_outputs(corpus_dir, clean_files, set())


def test_evil_corpus():
    setup_test_env()
    corpus_dir = "/app/tests/corpora/evil"
    assert os.path.isdir(corpus_dir), f"Evil corpus directory {corpus_dir} missing."
    evil_files = {f for f in os.listdir(corpus_dir) if f.endswith(".json")}

    res = run_script(corpus_dir)
    assert res.returncode == 0, f"Script failed on evil corpus:\n{res.stderr}"

    accepted = get_accepted_files()
    rejected = get_rejected_files()
    wrongly_accepted = evil_files.intersection(accepted)
    assert not wrongly_accepted, (
        f"{len(wrongly_accepted)} of {len(evil_files)} evil files bypassed sanitization: "
        f"{wrongly_accepted}"
    )
    missing_rejected = evil_files - rejected
    assert not missing_rejected, (
        f"{len(missing_rejected)} evil files were NOT logged: {missing_rejected}"
    )
    assert_exact_outputs(corpus_dir, set(), evil_files)


def oracle_accepts(obj):
    if not isinstance(obj, dict):
        return False
    path = obj.get("mount_path")
    quota = obj.get("quota_bytes")
    timezone = obj.get("log_timezone")
    if not isinstance(path, str) or not path.startswith("/"):
        return False
    normalized = posixpath.normpath(path)
    try:
        if normalized == "/data" or posixpath.commonpath(["/data", normalized]) != "/data":
            return False
    except ValueError:
        return False
    if type(quota) is not int or quota <= 0 or quota > 100 * 1024 * 1024 * 1024:
        return False
    if not isinstance(timezone, str):
        return False
    try:
        ZoneInfo(timezone)
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return True


def test_hidden_mixed_corpus_and_exact_copies():
    setup_test_env()
    corpus_dir = tempfile.mkdtemp(prefix="mount_requests_" + uuid.uuid4().hex + "_")
    rng = random.SystemRandom()
    maximum = 100 * 1024 * 1024 * 1024
    token = uuid.uuid4().hex

    objects = [
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": 1, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/a/../{token}", "quota_bytes": maximum, "log_timezone": "America/New_York"},
        {"service_id": token, "mount_path": f"/data//nested/{token}", "quota_bytes": rng.randint(2, maximum - 1), "log_timezone": "Etc/GMT+5"},
        {"service_id": token, "mount_path": "/data", "quota_bytes": 10, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": "/data/../etc", "quota_bytes": 10, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": "/data-escape/x", "quota_bytes": 10, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": "data/relative", "quota_bytes": 10, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": 0, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": -1, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": maximum + 1, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": True, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": "10", "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": 10.0, "log_timezone": "UTC"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": 10, "log_timezone": "Mars/Olympus"},
        {"service_id": token, "mount_path": f"/data/{token}", "quota_bytes": 10},
        [token, f"/data/{token}", 10, "UTC"],
    ]

    expected_accepted = set()
    expected_rejected = set()
    for obj in objects:
        name = uuid.uuid4().hex + ".json"
        raw = json.dumps(obj, ensure_ascii=False, indent=rng.choice([None, 2, 4]))
        if rng.choice([True, False]):
            raw += "\n"
        with open(os.path.join(corpus_dir, name), "w", encoding="utf-8") as f:
            f.write(raw)
        (expected_accepted if oracle_accepts(obj) else expected_rejected).add(name)

    malformed_name = uuid.uuid4().hex + ".json"
    with open(os.path.join(corpus_dir, malformed_name), "w") as f:
        f.write('{"mount_path": "/data/x", "quota_bytes":')
    expected_rejected.add(malformed_name)

    with open(os.path.join(corpus_dir, uuid.uuid4().hex + ".txt"), "w") as f:
        f.write("not a JSON request")

    res = run_script(corpus_dir)
    assert res.returncode == 0, f"Script failed on hidden mixed corpus:\n{res.stderr}"
    assert_exact_outputs(corpus_dir, expected_accepted, expected_rejected)


def test_script_requires_exactly_one_argument():
    no_arg = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    two_args = subprocess.run(
        ["python3", SCRIPT_PATH, "/tmp", "/tmp"], capture_output=True, text=True
    )
    assert no_arg.returncode != 0, "Script must reject invocation with no directory argument"
    assert two_args.returncode != 0, "Script must reject invocation with more than one argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
