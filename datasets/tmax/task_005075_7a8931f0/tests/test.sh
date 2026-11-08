#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import zipfile
import pytest

DETECTOR_PATH = "/home/user/detector"


def run_detector(payload):
    return subprocess.run(
        [DETECTOR_PATH],
        input=payload,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    ).returncode


def test_sshd_config_hardened():
    """Verify the sshd_config_hardened file exists and contains correct settings."""
    config_path = "/home/user/sshd_config_hardened"
    assert os.path.isfile(config_path), f"Missing sshd_config_hardened file at {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    # Preserve the original required checks.
    assert re.search(r"(?i)^\s*Port\s+22022\b", content, re.MULTILINE), "sshd_config_hardened is missing 'Port 22022'"
    assert re.search(r"(?i)^\s*PermitRootLogin\s+no\b", content, re.MULTILINE), "sshd_config_hardened is missing 'PermitRootLogin no'"

    # Ensure the matched lines are active global settings and are not contradicted.
    directives = []
    in_match = False
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        key = parts[0].lower()
        values = parts[1:]
        if key == "match":
            in_match = True
            continue
        directives.append((key, values, in_match))

    global_ports = [v for k, v, scoped in directives if k == "port" and not scoped]
    global_root = [v for k, v, scoped in directives if k == "permitrootlogin" and not scoped]
    assert global_ports, "Port 22022 must be an active global SSH directive"
    assert global_root, "PermitRootLogin no must be an active global SSH directive"
    assert all(v == ["22022"] for k, v, _ in directives if k == "port"), "Conflicting or invalid Port directive"
    assert all(len(v) == 1 and v[0].lower() == "no" for k, v, _ in directives if k == "permitrootlogin"), "Conflicting or invalid PermitRootLogin directive"


def test_detector_executable():
    """Verify the detector script exists and is executable."""
    assert os.path.isfile(DETECTOR_PATH), f"Missing detector script at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector script at {DETECTOR_PATH} is not executable"


def test_adversarial_corpus():
    """Verify the detector correctly classifies the supplied evil and clean corpora."""
    zip_path = "/app/evidence.zip"
    password = b"alphatango7"

    assert os.path.isfile(zip_path), f"Missing evidence.zip at {zip_path}"

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with zipfile.ZipFile(zip_path, "r") as zf:
                zf.extractall(path=tmpdir, pwd=password)
        except Exception as e:
            pytest.fail(f"Failed to extract {zip_path} with password {password.decode()}: {e}")

        evil_dir = os.path.join(tmpdir, "evil")
        clean_dir = os.path.join(tmpdir, "clean")

        assert os.path.isdir(evil_dir), "Extracted zip is missing 'evil' directory"
        assert os.path.isdir(clean_dir), "Extracted zip is missing 'clean' directory"

        evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
        clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

        evil_bypassed = []
        evil_wrong_code = []
        for filename in evil_files:
            filepath = os.path.join(evil_dir, filename)
            with open(filepath, "rb") as f:
                payload = f.read()

            returncode = run_detector(payload)
            if returncode == 0:
                evil_bypassed.append(filename)
            if returncode != 1:
                evil_wrong_code.append((filename, returncode))

        clean_modified = []
        for filename in clean_files:
            filepath = os.path.join(clean_dir, filename)
            with open(filepath, "rb") as f:
                payload = f.read()

            if run_detector(payload) != 0:
                clean_modified.append(filename)

        error_msgs = []
        if evil_bypassed:
            error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if evil_wrong_code:
            error_msgs.append("evil inputs must exit exactly 1: " + ", ".join(f"{n}={c}" for n, c in evil_wrong_code))
        if clean_modified:
            error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

        if error_msgs:
            pytest.fail("; ".join(error_msgs))


def random_label(min_len=8, max_len=18):
    alphabet = string.ascii_lowercase + string.digits
    length = min_len + secrets.randbelow(max_len - min_len + 1)
    return secrets.choice(string.ascii_lowercase) + "".join(secrets.choice(alphabet) for _ in range(length - 1))


def mixed_case_scheme(scheme):
    return "".join(ch.upper() if secrets.randbelow(2) else ch for ch in scheme)


def test_detector_on_unseen_randomized_urls():
    """Exercise semantic URL classes with values generated only after the agent has finished."""
    cases = []
    for _ in range(12):
        a, b, c = random_label(), random_label(), random_label()
        host = f"{a}.{b}.test"
        path = f"/{b}/{c}"
        http = mixed_case_scheme("http")
        https = mixed_case_scheme("https")

        clean = [
            f"/{a}",
            f"/{a}/{b}/{c}",
            f"{a}.html",
            f"{a}/{b}.html",
            f"/login?success=true&token={c}",
            f"/static/{a}-{b}.png",
        ]
        evil = [
            f"{http}://{host}{path}",
            f"{https}://{host}{path}",
            f"//{host}{path}",
            f"{https}:{host}{path}",
            f"\\/\\/{host}{path}",
            f"http://localhost@{host}{path}",
            f"http://{a}.invalid/login?next=http://{host}{path}",
            f"http://{a}.invalid/login?next=//{host}{path}",
        ]
        cases.extend((url, 0) for url in clean)
        cases.extend((url, 1) for url in evil)

    # Randomize ordering and line endings so behavior cannot depend on corpus position.
    secrets.SystemRandom().shuffle(cases)
    failures = []
    for url, expected in cases:
        ending = secrets.choice(["", "\n", "\r\n"])
        actual = run_detector((url + ending).encode("utf-8"))
        if actual != expected:
            failures.append((url, expected, actual))

    assert not failures, "Randomized URL classification failures: " + "; ".join(
        f"{url!r} expected exit {expected}, got {actual}" for url, expected, actual in failures[:10]
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
