#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/audit.sh"
ENGINE_DIR = "/app/rbac_engine-0.1.0"
BINARY_PATH = os.path.join(ENGINE_DIR, "target/release/rbac-cli")
REAL_BINARY_PATH = os.path.join(ENGINE_DIR, "target/release/rbac-cli.verifier-real")
SCHEMA_PATH = "/app/schema/system_graph.yaml"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
CALL_LOG = "/tmp/rbac-cli-calls.log"


@pytest.fixture(scope="session", autouse=True)
def build_and_instrument_engine():
    # Force a clean build so the submitted Makefile and compile-time environment
    # are actually exercised rather than accepting a stale artifact.
    shutil.rmtree(os.path.join(ENGINE_DIR, "target"), ignore_errors=True)
    env = os.environ.copy()
    env.pop("RBAC_GRAPH_STRICT", None)
    result = subprocess.run(
        ["make", "build"], cwd=ENGINE_DIR, env=env,
        capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, (
        f"make build failed with code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY_PATH), f"Compiled binary missing: {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary is not executable: {BINARY_PATH}"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "rbac-cli is not a compiled ELF binary"

    # Confirm that the corrected build enabled strict denial behavior.
    with tempfile.TemporaryDirectory() as td:
        clean = os.path.join(td, "request-a.json")
        evil = os.path.join(td, "request-b.json")
        with open(clean, "w") as f:
            json.dump({"user": "user1", "resource": "resource1", "marker": uuid.uuid4().hex}, f)
        with open(evil, "w") as f:
            json.dump({"user": "user2", "resource": "resource1", "marker": "evil-" + uuid.uuid4().hex}, f)
        clean_result = subprocess.run([BINARY_PATH, SCHEMA_PATH, clean], capture_output=True, text=True)
        evil_result = subprocess.run([BINARY_PATH, SCHEMA_PATH, evil], capture_output=True, text=True)
        assert clean_result.returncode == 0 and clean_result.stdout.strip() == "ALLOW"
        assert evil_result.returncode == 0 and evil_result.stdout.strip() == "DENY", (
            "rbac-cli was not built with strict access checking enabled"
        )

    # Instrument the required compiled artifact so each classifier run must
    # actually invoke it with the required schema and request path.
    os.replace(BINARY_PATH, REAL_BINARY_PATH)
    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\t%s\\n' "$#" "${{1-}}" "${{2-}}" >> {CALL_LOG}
exec {REAL_BINARY_PATH} "$@"
'''
    with open(BINARY_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(BINARY_PATH, 0o755)
    yield


def run_audit_and_require_engine(request_path):
    try:
        os.remove(CALL_LOG)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [SCRIPT_PATH, request_path], capture_output=True, text=True, timeout=20
    )

    assert os.path.isfile(CALL_LOG), "audit.sh did not invoke the compiled rbac-cli"
    with open(CALL_LOG) as f:
        calls = [line.rstrip("\n").split("\t") for line in f if line.strip()]
    assert any(
        len(call) == 3 and call[0] == "2" and
        call[1] == SCHEMA_PATH and call[2] == request_path
        for call in calls
    ), (
        "audit.sh did not invoke rbac-cli with exactly the required schema "
        "and request file"
    )
    return result


def expected_from_engine(request_path):
    result = subprocess.run(
        [REAL_BINARY_PATH, SCHEMA_PATH, request_path],
        capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0
    expected = result.stdout.strip()
    assert expected in ("ALLOW", "DENY")
    return expected


def test_audit_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_clean_corpus_allow():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".json")]
    assert len(clean_files) > 0, f"No JSON files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = run_audit_and_require_engine(filepath)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "ALLOW":
            failed_files.append((filename, result.returncode, output))

    if failed_files:
        details = ", ".join([f"{f} (code {c}, out {o})" for f, c, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files failed (expected ALLOW). Details: {details}")


def test_evil_corpus_deny():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".json")]
    assert len(evil_files) > 0, f"No JSON files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = run_audit_and_require_engine(filepath)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "DENY":
            failed_files.append((filename, result.returncode, output))

    if failed_files:
        details = ", ".join([f"{f} (code {c}, out {o})" for f, c, o in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected DENY). Details: {details}")


def test_generated_requests_are_evaluated_by_engine():
    # Use fresh paths and randomized request contents, and derive every expected
    # answer from the freshly built engine rather than directory membership.
    with tempfile.TemporaryDirectory(prefix="rbac-generated-") as td:
        requests = []
        for index in range(8):
            token = uuid.uuid4().hex
            body = {
                "user": f"subject-{token}",
                "resource": f"object-{uuid.uuid4().hex}",
                "request_id": uuid.uuid4().hex,
                "note": (f"evil-{token}" if index % 2 else f"review-{token}"),
            }
            path = os.path.join(td, f"case-{uuid.uuid4().hex}.json")
            with open(path, "w") as f:
                json.dump(body, f)
            requests.append(path)

        for path in requests:
            expected = expected_from_engine(path)
            result = run_audit_and_require_engine(path)
            assert result.returncode == 0, f"audit.sh returned {result.returncode} for {path}"
            assert result.stdout.strip() == expected, (
                f"audit.sh returned {result.stdout.strip()!r}, expected {expected!r} for {path}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
