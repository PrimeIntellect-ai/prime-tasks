#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import subprocess
import tempfile
import pytest

PAYLOAD_FILE = "/home/user/injected_payload.txt"
TEST_SCRIPT = "/home/user/test_artifact.sh"
V1_MANIFEST = "/home/user/build_v1_manifest.json"
V2_MANIFEST = "/home/user/build_v2_manifest.json"


def newly_added_artifact():
    with open(V1_MANIFEST, encoding="utf-8") as f:
        v1 = json.load(f)
    with open(V2_MANIFEST, encoding="utf-8") as f:
        v2 = json.load(f)

    old = {(item["name"], item["path"]) for item in v1["artifacts"]}
    added = sorted(
        item for item in v2["artifacts"]
        if (item["name"], item["path"]) not in old
    )
    assert len(added) == 1, f"Expected exactly one newly added artifact, found {added!r}"
    return added[0]


def artifact_output():
    artifact = newly_added_artifact()["path"]
    assert os.path.isfile(artifact), f"Artifact {artifact} does not exist."
    assert os.access(artifact, os.X_OK), f"Artifact {artifact} is not executable."
    with open(artifact, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Artifact {artifact} is not an ELF binary."
    result = subprocess.run([artifact], capture_output=True, timeout=5)
    assert result.returncode == 0, f"Artifact exited with code {result.returncode}."
    return artifact, result.stdout


def test_injected_payload_file():
    assert os.path.isfile(PAYLOAD_FILE), f"File {PAYLOAD_FILE} does not exist."
    with open(PAYLOAD_FILE, "rb") as f:
        content = f.read()

    # Retain the original header assertion.
    assert b"X-Malicious-Backdoor: active" in content, \
        "The payload file does not contain the expected malicious header string."

    # The saved bytes, including all CR/LF bytes, must exactly match the binary output.
    _, expected = artifact_output()
    assert content == expected, \
        f"Payload bytes do not exactly match artifact output: {content!r} != {expected!r}"


def test_test_artifact_script_exists_and_executable():
    assert os.path.isfile(TEST_SCRIPT), f"Script {TEST_SCRIPT} does not exist."
    assert os.access(TEST_SCRIPT, os.X_OK), f"Script {TEST_SCRIPT} is not executable."


def test_test_artifact_script_execution():
    try:
        result = subprocess.run([TEST_SCRIPT], capture_output=True, text=True, timeout=5)
    except Exception as e:
        pytest.fail(f"Failed to execute {TEST_SCRIPT}: {e}")

    assert result.returncode == 0, \
        f"{TEST_SCRIPT} failed with exit code {result.returncode}. Stderr: {result.stderr}"


def test_script_executes_artifact_and_detects_bad_output():
    artifact, _ = artifact_output()
    artifact_dir = os.path.dirname(artifact)

    fd, backup = tempfile.mkstemp(prefix=".verifier-artifact-backup-", dir=artifact_dir)
    os.close(fd)
    os.unlink(backup)

    fd, marker = tempfile.mkstemp(prefix="verifier-artifact-marker-", dir="/tmp")
    os.close(fd)
    os.unlink(marker)

    os.rename(artifact, backup)
    try:
        wrapper = (
            "#!/bin/sh\n"
            f"printf '%s\\n' invoked > {shlex.quote(marker)}\n"
            "printf '%s\\n' 'incorrect artifact output'\n"
        )
        with open(artifact, "w", encoding="utf-8", newline="\n") as f:
            f.write(wrapper)
        os.chmod(artifact, 0o755)

        try:
            result = subprocess.run([TEST_SCRIPT], capture_output=True, text=True, timeout=5)
        except Exception as e:
            pytest.fail(f"Failed to execute {TEST_SCRIPT} against altered artifact: {e}")

        assert os.path.isfile(marker), \
            "The test script did not execute the newly added artifact."
        assert result.returncode == 1, \
            f"The test script did not reject incorrect artifact output with exit code 1; got {result.returncode}."
    finally:
        if os.path.lexists(artifact):
            os.unlink(artifact)
        os.rename(backup, artifact)
        if os.path.exists(marker):
            os.unlink(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
