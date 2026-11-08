#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tarfile

SCRIPT_PATH = "/home/user/config_sanitizer.py"
ARCHIVE_PATH = "/home/user/clean_configs.tar.gz"


def run_sanitizer(content):
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        input=content.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_adversarial_corpus_evil():
    # Preserve the original semantic cases without exposing a corpus in the image.
    evil_cases = [
        "PermitRootLogin yes\n",
        "PasswordAuthentication yes\n",
        "ListenAddress 0.0.0.0\n",
        "host: 8.8.8.8\n",
        "server 172.16.0.1\n",
    ]

    # Add fresh cases so a submission cannot hardcode the fixed examples.
    rng = random.SystemRandom()
    for _ in range(30):
        kind = rng.randrange(5)
        if kind == 0:
            content = f"service_{rng.randrange(1 << 40)}=enabled\nPermitRootLogin yes\n"
        elif kind == 1:
            content = f"# token {rng.randrange(1 << 40)}\nPasswordAuthentication yes\n"
        elif kind == 2:
            content = f"ListenAddress 0.0.0.0\nPort {rng.randrange(1024, 65536)}\n"
        elif kind == 3:
            ip = f"{rng.randrange(11, 127)}.{rng.randrange(256)}.{rng.randrange(256)}.{rng.randrange(1, 255)}"
            content = f'{{"upstream_{rng.randrange(1 << 40)}": "{ip}"}}\n'
        else:
            # Other loopback addresses are not covered by the sole 127.0.0.1 exception.
            ip = f"127.{rng.randrange(1, 256)}.{rng.randrange(256)}.{rng.randrange(1, 255)}"
            content = f"backend = {ip}\n"
        evil_cases.append(content)

    bypassed = [repr(case) for case in evil_cases if run_sanitizer(case) != 1]
    assert not bypassed, f"{len(bypassed)} evil configurations bypassed: {', '.join(bypassed[:5])}"


def test_adversarial_corpus_clean():
    # Preserve the original semantic cases without exposing a corpus in the image.
    clean_cases = [
        "PermitRootLogin no\n",
        "PasswordAuthentication no\n",
        "ListenAddress 127.0.0.1\n",
        "host: 10.1.2.3\n",
        "server 192.168.1.1\n",
    ]

    rng = random.SystemRandom()
    for _ in range(30):
        ip10 = f"10.{rng.randrange(256)}.{rng.randrange(256)}.{rng.randrange(256)}"
        ip192 = f"192.168.{rng.randrange(256)}.{rng.randrange(256)}"
        content = (
            f"# generated {rng.randrange(1 << 40)}\n"
            "PermitRootLogin no\n"
            "PasswordAuthentication no\n"
            f"primary = {ip10}\n"
            f"secondary = {ip192}\n"
            "healthcheck = 127.0.0.1\n"
        )
        clean_cases.append(content)

    rejected = [repr(case) for case in clean_cases if run_sanitizer(case) != 0]
    assert not rejected, f"{len(rejected)} clean configurations rejected: {', '.join(rejected[:5])}"


def test_archive_exists_and_contents():
    assert os.path.exists(ARCHIVE_PATH), f"Archive missing at {ARCHIVE_PATH}"
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive"

    expected = {
        "nginx.conf": "server {\n  listen 80;\n  server_name localhost;\n}\n",
        "app_config.json": '{\n  "app_name": "myapp",\n  "version": "1.0"\n}\n',
    }

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        file_members = [m for m in members if not m.isdir()]
        basenames = [os.path.basename(m.name) for m in file_members]

        expected_files = set(expected)
        actual_files = set(basenames)
        missing = expected_files - actual_files
        extra = actual_files - expected_files

        assert not missing, f"Missing expected clean configs in archive: {', '.join(missing)}"
        assert not extra, f"Archive contains unexpected files (evil configs or others): {', '.join(extra)}"
        assert len(file_members) == len(expected), "Archive contains duplicate or non-regular entries"

        for member in file_members:
            basename = os.path.basename(member.name)
            assert member.isfile(), f"Archive entry {member.name} is not a regular file"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive entry {member.name}"
            content = extracted.read().decode("utf-8")
            assert content == expected[basename], f"Incorrect extracted content for {basename}"
            assert run_sanitizer(content) == 0, f"Archived configuration {basename} is not clean"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
