#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import subprocess
import tarfile
import uuid
from collections import Counter
from pathlib import Path

SCRIPT = Path("/home/user/scan_artifacts.py")
ARCHIVE = Path("/home/user/artifacts/release_v2.tar.gz")
LOG = Path("/home/user/malicious_paths.txt")

ORIGINAL_EXPECTED = {
    "../../etc/shadow",
    "/root/.ssh/authorized_keys",
    "bin/../../var/run/daemon.pid",
}


def run_script():
    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Scanner exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_original_checks():
    assert os.path.isfile(SCRIPT), f"Expected script at {SCRIPT} does not exist."
    assert os.path.isfile(LOG), f"Expected output file at {LOG} does not exist."

    with open(LOG, "r") as f:
        actual_paths = set(line.strip() for line in f if line.strip())

    assert actual_paths == ORIGINAL_EXPECTED, (
        f"The contents of {LOG} are incorrect.\n"
        f"Expected: {ORIGINAL_EXPECTED}\n"
        f"Actual: {actual_paths}"
    )


def add_member(tar, name):
    payload = b"verifier payload"
    info = tarfile.TarInfo(name=name)
    info.size = len(payload)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(payload))


def token_named_paths(token):
    found = []
    for root in ("/home", "/tmp"):
        for directory, dirnames, filenames in os.walk(root):
            for name in dirnames + filenames:
                if token in name:
                    found.append(os.path.join(directory, name))
    return found


def test_scanner_executes_and_scans_stream():
    assert os.path.isfile(SCRIPT), f"Expected script at {SCRIPT} does not exist."

    # Execute against the supplied archive and retain the original assertions.
    LOG.unlink(missing_ok=True)
    run_script()
    assert_original_checks()

    original_archive = ARCHIVE.read_bytes()
    token = "scanverify_" + uuid.uuid4().hex
    malicious = [
        f"../{token}_up.txt",
        f"/tmp/{token}_absolute.txt",
        f"folder/../../{token}_nested.txt",
    ]
    safe = [
        f"{token}_safe/file.txt",
        f"folder/../{token}_inside.txt",
        f"./{token}_ordinary.txt",
    ]

    try:
        with tarfile.open(ARCHIVE, "w:gz") as tar:
            for name in [safe[0], malicious[0], safe[1], malicious[1],
                         malicious[2], safe[2]]:
                add_member(tar, name)

        dynamic_archive = ARCHIVE.read_bytes()
        LOG.unlink(missing_ok=True)
        run_script()

        assert ARCHIVE.read_bytes() == dynamic_archive, "Scanner modified the archive."
        assert os.path.isfile(LOG), f"Expected output file at {LOG} does not exist."
        actual_lines = LOG.read_text().splitlines()
        assert Counter(actual_lines) == Counter(malicious), (
            "Scanner did not report the exact original malicious member names.\n"
            f"Expected: {malicious}\nActual: {actual_lines}"
        )

        extracted = token_named_paths(token)
        assert not extracted, f"Scanner extracted archive members: {extracted}"
    finally:
        ARCHIVE.write_bytes(original_archive)
        LOG.unlink(missing_ok=True)
        run_script()

    # Leave the required output generated from the real archive and re-check it.
    assert_original_checks()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
