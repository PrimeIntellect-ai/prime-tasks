#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import ipaddress
import os
import random
import secrets
import subprocess
import tempfile


def run_detector(executable, path):
    proc = subprocess.run([executable, path], capture_output=True, timeout=5)
    return proc.returncode


def random_public_ipv4():
    while True:
        value = ipaddress.IPv4Address(secrets.randbits(32))
        if not (value.is_private or value.is_loopback or value.is_link_local or
                value.is_multicast or value.is_reserved or value.is_unspecified):
            return str(value)


def test_detector_compiles_and_works():
    c_source = "/home/user/detector.c"
    executable = "/home/user/detector"

    assert os.path.isfile(c_source), f"Source file {c_source} does not exist."

    compile_cmd = ["gcc", c_source, "-o", executable]
    compile_proc = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compile_proc.returncode == 0, f"Failed to compile {c_source}:\n{compile_proc.stderr}"
    assert os.path.isfile(executable), f"Executable {executable} was not created."
    assert os.access(executable, os.X_OK), f"Executable {executable} is not executable."

    evil_files = glob.glob("/app/corpora/evil/*")
    clean_files = glob.glob("/app/corpora/clean/*")
    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    # Preserve the valid supplied-corpus checks. The UDP sample is accepted because
    # the observed exfiltration scheme in the incident is specifically tcp://.
    supplied_expectations = {
        "/app/corpora/evil/1.txt": 1,
        "/app/corpora/evil/2.txt": 0,
        "/app/corpora/clean/1.txt": 0,
        "/app/corpora/clean/2.txt": 0,
    }
    supplied_errors = []
    for path, expected in supplied_expectations.items():
        assert os.path.isfile(path), f"Expected corpus file {path} is missing."
        actual = run_detector(executable, path)
        if actual != expected:
            supplied_errors.append(f"{os.path.basename(path)} returned {actual}, expected {expected}")
    assert not supplied_errors, " | ".join(supplied_errors)

    # Generate neutrally named, randomly assigned cases so behavior cannot be based
    # on the known corpus directories or filenames.
    cases = []
    for _ in range(10):
        ip = random_public_ipv4()
        port = secrets.randbelow(64512) + 1024
        password = "pw_" + secrets.token_hex(10)
        extra = "job_" + secrets.token_hex(4)
        internal = "backup-" + secrets.token_hex(4) + ".internal.corp"

        malicious = [
            f"data_sync --password {password} --target tcp://{ip}:{port}",
            f"data_sync --target tcp://{ip}:{port} --password {password}",
            f"data_sync --verbose --password {password} --target tcp://{ip}:{port} --job {extra}",
        ]
        clean = [
            f"data_sync --password {password} --target udp://{ip}:{port}",
            f"data_sync --password {password} --target ssh://{ip}/backup",
            f"data_sync --password {password} --target /mnt/{extra}/",
            f"data_sync --password {password} --target tcp://{internal}:{port}",
            f"data_sync --target tcp://{ip}:{port}",
            f"other_sync --password {password} --target tcp://{ip}:{port}",
            f"data_sync --password tcp://{ip}:{port} --target /mnt/{extra}/",
        ]
        cases.extend((text, 1) for text in malicious)
        cases.extend((text, 0) for text in clean)

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="detector-cases-") as directory:
        for text, expected in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text + "\n")
            actual = run_detector(executable, path)
            if actual != expected:
                failures.append(f"returned {actual}, expected {expected}, input={text!r}")

    assert not failures, "Detector misclassified generated cases:\n" + "\n".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
