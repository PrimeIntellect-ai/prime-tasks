#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import shutil
import struct
import subprocess
import tempfile
import uuid
import zipfile

import pytest

SCAN_SCRIPT = "/home/user/scan.py"
RESULTS_FILE = "/home/user/results.json"
CORE_FILE = "/app/py-archive-validator-1.0.0/validator/core.py"


def run_scan(directory, env=None):
    assert os.path.isfile(SCAN_SCRIPT), f"Scan script not found at {SCAN_SCRIPT}"
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    run_env = os.environ.copy()
    run_env["PYTHONDONTWRITEBYTECODE"] = "1"
    if env:
        run_env.update(env)
    result = subprocess.run(
        ["python3", SCAN_SCRIPT, directory],
        capture_output=True,
        text=True,
        env=run_env,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"scan.py failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(RESULTS_FILE), f"Results file not found at {RESULTS_FILE}"
    try:
        with open(RESULTS_FILE, "r") as f:
            results = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("results.json is not valid JSON")
    assert isinstance(results, dict), "results.json must contain a single JSON object"
    return results


def make_zip(path, members):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as zf:
        for member, content in members:
            zf.writestr(member, content)


def corrupt_stored_zip(path, member):
    payload = b"integrity-check-payload"
    make_zip(path, [(member, payload)])
    with open(path, "r+b") as f:
        header = f.read(30)
        assert header[:4] == b"PK\x03\x04"
        fields = struct.unpack("<IHHHHHIIIHH", header)
        name_len, extra_len = fields[-2], fields[-1]
        data_offset = 30 + name_len + extra_len
        f.seek(data_offset + len(payload) // 2)
        old = f.read(1)
        f.seek(data_offset + len(payload) // 2)
        f.write(bytes([old[0] ^ 0xFF]))


def test_scan_clean_corpus():
    clean_dir = "/app/corpora/clean"
    results = run_scan(clean_dir)
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".zip")]
    failed_clean = [f for f in clean_files if results.get(f) != "clean"]
    if failed_clean:
        pytest.fail(
            f"{len(failed_clean)} of {len(clean_files)} clean files modified/rejected: "
            + ", ".join(failed_clean)
        )


def test_scan_evil_corpus():
    evil_dir = "/app/corpora/evil"
    results = run_scan(evil_dir)
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".zip")]
    failed_evil = [f for f in evil_files if results.get(f) != "evil"]
    if failed_evil:
        pytest.fail(
            f"{len(failed_evil)} of {len(evil_files)} evil files bypassed: "
            + ", ".join(failed_evil)
        )


def test_banned_user():
    banned_file = "/home/user/banned.txt"
    assert os.path.isfile(banned_file), f"Banned user file not found at {banned_file}"
    with open(banned_file, "r") as f:
        banned_user = f.read().strip()
    assert banned_user == "eve_hacker", (
        f"Expected banned user 'eve_hacker', but got '{banned_user}'"
    )


def test_fixed_validator_core_and_dynamic_classification():
    assert os.path.isfile(CORE_FILE), f"Validator core not found at {CORE_FILE}"

    spec = importlib.util.spec_from_file_location("audited_validator_core", CORE_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "is_safe_path")

    for safe in ["document.txt", "docs/manual/readme.txt", "folder/...notes/file.txt"]:
        assert module.is_safe_path(safe) is True, f"Safe path rejected: {safe!r}"
    for unsafe in [
        "../escape.txt",
        "safe/../../escape.txt",
        "/etc/passwd",
        "..\\..\\boot.ini",
        "folder\\..\\..\\escape.txt",
        "C:\\Windows\\System32\\cmd.exe",
        "\\\\server\\share\\payload.txt",
    ]:
        assert module.is_safe_path(unsafe) is False, f"Unsafe path accepted: {unsafe!r}"

    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="archive-input-") as directory:
        cases = {}
        member_names = []

        def add_case(members, expected):
            filename = uuid.uuid4().hex + ".zip"
            make_zip(os.path.join(directory, filename), members)
            cases[filename] = expected
            member_names.extend(name for name, _ in members)

        add_case([("nested/" + token + "/report.txt", b"ok")], "clean")
        add_case([("../" + token + ".txt", b"bad")], "evil")
        add_case([("base/../../" + token + ".txt", b"bad")], "evil")
        add_case([("..\\..\\" + token + ".txt", b"bad")], "evil")
        add_case([("D:\\temp\\" + token + ".txt", b"bad")], "evil")
        add_case([("/var/tmp/" + token + ".txt", b"bad")], "evil")

        invalid_name = uuid.uuid4().hex + ".zip"
        with open(os.path.join(directory, invalid_name), "wb") as f:
            f.write(os.urandom(173))
        cases[invalid_name] = "invalid"

        corrupt_name = uuid.uuid4().hex + ".zip"
        corrupt_stored_zip(os.path.join(directory, corrupt_name), "data/" + token + ".bin")
        cases[corrupt_name] = "invalid"

        trace_file = os.path.join(directory, "validator-calls.jsonl")
        with open(CORE_FILE, "r") as f:
            original_core = f.read()
        instrumentation = r'''

_original_is_safe_path_for_verifier = is_safe_path
def is_safe_path(filename):
    import json as _trace_json
    import os as _trace_os
    _trace_path = _trace_os.environ.get("SCAN_VALIDATOR_TRACE")
    if _trace_path:
        with open(_trace_path, "a") as _trace_file:
            _trace_file.write(_trace_json.dumps(filename) + "\\n")
    return _original_is_safe_path_for_verifier(filename)
'''
        try:
            with open(CORE_FILE, "w") as f:
                f.write(original_core)
                f.write(instrumentation)
            shutil.rmtree(os.path.join(os.path.dirname(CORE_FILE), "__pycache__"), ignore_errors=True)
            results = run_scan(directory, {"SCAN_VALIDATOR_TRACE": trace_file})
        finally:
            with open(CORE_FILE, "w") as f:
                f.write(original_core)
            shutil.rmtree(os.path.join(os.path.dirname(CORE_FILE), "__pycache__"), ignore_errors=True)

        assert results == cases, f"Unexpected classifications: {results!r}; expected {cases!r}"
        assert os.path.isfile(trace_file), "scan.py did not call validator.core.is_safe_path"
        with open(trace_file, "r") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        for member in member_names:
            assert member in calls, f"Validator was not used for archive member {member!r}"


def test_banned_user_is_derived_from_log_and_scan_results():
    recent = "/app/recent_uploads"
    log_path = "/app/upload_service.log"
    suffix = uuid.uuid4().hex
    recent_backup = recent + ".verifier-backup-" + suffix
    log_backup = log_path + ".verifier-backup-" + suffix
    os.rename(recent, recent_backup)
    os.rename(log_path, log_backup)
    os.mkdir(recent)

    top_user = "user_" + uuid.uuid4().hex
    other_user = "user_" + uuid.uuid4().hex
    third_user = "user_" + uuid.uuid4().hex
    uploads = []
    expected = {}

    def add_upload(user, classification):
        filename = uuid.uuid4().hex + ".zip"
        path = os.path.join(recent, filename)
        if classification == "clean":
            make_zip(path, [("docs/" + uuid.uuid4().hex + ".txt", b"ok")])
        elif classification == "evil":
            make_zip(path, [("../../" + uuid.uuid4().hex + ".txt", b"bad")])
        else:
            with open(path, "wb") as f:
                f.write(os.urandom(91))
        uploads.append((user, filename))
        expected[filename] = classification

    for _ in range(4):
        add_upload(top_user, "evil")
    add_upload(top_user, "clean")
    for _ in range(2):
        add_upload(other_user, "evil")
    add_upload(other_user, "clean")
    add_upload(third_user, "invalid")
    random.SystemRandom().shuffle(uploads)

    try:
        with open(log_path, "w") as f:
            for user, filename in uploads:
                f.write("[START UPLOAD]\n")
                f.write("Timestamp: 2026-01-01T00:00:00Z\n")
                f.write(f"User: {user}\n")
                f.write(f"Archive: {filename}\n")
                f.write("[END UPLOAD]\n")

        results = run_scan(recent)
        assert results == expected
        assert os.path.isfile("/home/user/banned.txt")
        with open("/home/user/banned.txt", "r") as f:
            actual = f.read().strip()
        assert actual == top_user, f"Expected dynamically derived offender {top_user!r}, got {actual!r}"
    finally:
        shutil.rmtree(recent, ignore_errors=True)
        if os.path.exists(log_path):
            os.remove(log_path)
        os.rename(recent_backup, recent)
        os.rename(log_backup, log_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
