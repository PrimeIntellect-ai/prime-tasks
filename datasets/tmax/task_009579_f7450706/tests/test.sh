#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import hashlib
import urllib.parse

CANONICAL_EXPECTED_PATHS = {
    "/home/user/scripts/backdoor.sh",
    "/home/user/scripts/shell.sh",
}


def get_expected_critical_findings():
    log_file = "/home/user/service/logs/server.log"
    uploads_dir = "/home/user/service/uploads/"

    assert os.path.isfile(log_file), f"Log file missing: {log_file}"

    expected_paths = set()

    with open(log_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            match = re.search(r"Token:\s*(\S+)\s*-\s*UploadedPath:\s*(\S+)", line)
            if not match:
                continue

            token = match.group(1)
            raw_path = match.group(2)

            if "../" not in raw_path and "..%2F" not in raw_path:
                continue

            token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
            if not token_hash.startswith("00"):
                continue

            unquoted_path = urllib.parse.unquote(raw_path)
            abs_path = os.path.normpath(os.path.join(uploads_dir, unquoted_path))

            if os.path.isfile(abs_path) and os.access(abs_path, os.X_OK):
                expected_paths.add(abs_path)

    return expected_paths


def test_critical_findings_file():
    findings_file = "/home/user/critical_findings.txt"
    assert os.path.isfile(findings_file), (
        f"The file {findings_file} does not exist. You need to create it."
    )

    with open(findings_file, "r") as f:
        actual_paths = set(line.strip() for line in f if line.strip())

    expected_paths = get_expected_critical_findings()

    # Ensure agent-writable logs, files, or permissions were not changed to
    # collapse the live expectation to an empty or incomplete set.
    assert expected_paths == CANONICAL_EXPECTED_PATHS, (
        "The audit source data or candidate files were modified: expected the "
        f"original critical paths {sorted(CANONICAL_EXPECTED_PATHS)}, but the "
        f"live audit produced {sorted(expected_paths)}"
    )

    missing = expected_paths - actual_paths
    extra = actual_paths - expected_paths

    error_msg = []
    if missing:
        error_msg.append(
            f"Missing expected executable malicious paths: {', '.join(missing)}"
        )
    if extra:
        error_msg.append(
            "Included incorrect paths (not executable, invalid token, or safe): "
            f"{', '.join(extra)}"
        )

    assert not missing and not extra, " | ".join(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
