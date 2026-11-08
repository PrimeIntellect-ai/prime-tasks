#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/detect_tunnels.py"


def run_detector(path=None):
    command = ["python3", SCRIPT_PATH]
    if path is not None:
        command.append(path)
    return subprocess.run(command, capture_output=True, timeout=5)


def test_part1_breach_frame():
    frame_file = "/home/user/breach_frame.txt"
    assert os.path.isfile(frame_file), f"Missing breach frame file at {frame_file}"

    with open(frame_file, "r") as f:
        content = f.read().strip()

    assert content == "145", f"Expected breach frame to be '145', but got '{content}'"


def test_part2_detect_tunnels():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Missing detect_tunnels.py script at {script_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus directory at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        result = run_detector(cf)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = run_detector(ef)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean files failed (expected exit code 0): {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil files bypassed (expected exit code 1): {', '.join(evil_failures)}")

    assert not error_messages, " | ".join(error_messages)


def test_part2_hidden_behavioral_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Missing detect_tunnels.py script at {SCRIPT_PATH}"

    token = secrets.token_hex(6)
    host = f"node-{token}.internal"
    user = f"acct{secrets.randbelow(9000) + 1000}"
    ssh_port = secrets.randbelow(50000) + 1024
    local_port = secrets.randbelow(40000) + 20000
    remote_port = secrets.randbelow(10000) + 10000
    socks_port = secrets.randbelow(5000) + 2000

    clean_cases = [
        "",
        "COMMAND\n",
        f"ssh {user}@{host}\n",
        f"ssh -p {ssh_port} -i /tmp/key-{token}.pem {user}@{host}\n",
        f"/usr/bin/ssh -v -o LogLevel=DEBUG backup@{host}\n",
        f"ssh -N {user}@{host}\n",
        f"ssh -l {user} {host}\n",
        f"sshd: {user}@pts/7\n",
        f"python3 worker.py --message 'ssh -L {local_port}:localhost:80 fake@host'\n",
        f"echo ssh -R {remote_port}:localhost:22 fake@host\n",
        f"ssh {user}@{host} echo -L is remote text\n",
        f"broken process line with an 'unterminated quote\nssh -p {ssh_port} {user}@{host}\n",
    ]

    evil_cases = [
        f"ssh\t-L\t{local_port}:127.0.0.1:80\t{user}@{host}\n",
        f"/usr/bin/ssh -R {remote_port}:localhost:22 {user}@{host}\n",
        f"ssh -D {socks_port} proxy@{host}\n",
        f"ssh -vNL {local_port}:localhost:9000 {user}@{host}\n",
        f"ssh -fR{remote_port}:localhost:22 {user}@{host}\n",
        f"ssh -L{local_port}:localhost:443 {user}@{host}\n",
        f"ssh -NTD{socks_port} {user}@{host}\n",
        f"python3 harmless.py\nbroken 'unterminated text\nssh -o ExitOnForwardFailure=yes -L {local_port}:db.internal:5432 {user}@{host}\n",
        f"ssh -p {ssh_port} {user}@{host}\n/usr/local/bin/ssh -N -R {remote_port}:127.0.0.1:22 relay@{host}\n",
    ]

    cases = [(0, text) for text in clean_cases] + [(1, text) for text in evil_cases]
    random.SystemRandom().shuffle(cases)

    # Every case is written to the same randomly named path, preventing a detector
    # from inferring the answer from clean/evil directory names or filenames.
    with tempfile.TemporaryDirectory(prefix=f"tunnel-audit-{token}-") as temp_dir:
        case_path = os.path.join(temp_dir, f"processes-{secrets.token_hex(8)}.log")
        failures = []
        for expected, text in cases:
            with open(case_path, "w", encoding="utf-8") as handle:
                handle.write(text)
            result = run_detector(case_path)
            if result.returncode != expected:
                failures.append(
                    f"expected {expected}, got {result.returncode} for content {text!r}; "
                    f"stderr={result.stderr[:300]!r}"
                )
        assert not failures, "Hidden behavioral failures: " + " | ".join(failures)


def test_part2_missing_file_and_argument_errors():
    assert os.path.isfile(SCRIPT_PATH), f"Missing detect_tunnels.py script at {SCRIPT_PATH}"

    missing = os.path.join(
        tempfile.gettempdir(),
        f"definitely-missing-{secrets.token_hex(16)}.txt",
    )
    assert not os.path.exists(missing)

    missing_result = run_detector(missing)
    assert missing_result.returncode != 0, "A missing input file must produce a nonzero exit code"
    assert b"Traceback" not in missing_result.stderr, "Missing files must be handled without an uncaught traceback"

    no_argument_result = run_detector()
    assert no_argument_result.returncode != 0, "Invoking the detector without its required argument must fail"
    assert b"Traceback" not in no_argument_result.stderr, "Argument errors must be handled without an uncaught traceback"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
