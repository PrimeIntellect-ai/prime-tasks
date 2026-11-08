#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

SECRET_FILE = "/home/user/secret.txt"
OUTPUT_LOG = "/home/user/output.log"
REPO = "/home/user/data_pipeline"
PROCESS_SCRIPT = os.path.join(REPO, "process_all.sh")
BINARY = os.path.join(REPO, "target/debug/data_parser")
INCOMING = "/home/user/incoming_data"
TOKEN = "sk-9942b-secret-token"

# Preserve the original verifier assertions.
def test_secret_file_content():
    assert os.path.isfile(SECRET_FILE), f"{SECRET_FILE} is missing. You need to recover the secret and save it here."
    with open(SECRET_FILE, "r") as f:
        content = f.read().strip()
    assert content == TOKEN, f"Content of {SECRET_FILE} is incorrect. Expected the recovered API token."


def test_output_log_content():
    assert os.path.isfile(OUTPUT_LOG), f"{OUTPUT_LOG} is missing. Did you run the fixed process_all.sh script?"
    with open(OUTPUT_LOG, "r") as f:
        content = f.read()

    expected_alpha = "PROCESSED: leaf_alpha WITH sk-9942b-secret-token"
    expected_beta = "PROCESSED: leaf_beta WITH sk-9942b-secret-token"

    assert expected_alpha in content, f"Expected to find '{expected_alpha}' in {OUTPUT_LOG}. Check your Rust parser logic and script."
    assert expected_beta in content, f"Expected to find '{expected_beta}' in {OUTPUT_LOG}. Check your Rust parser logic and script."


def run_checked(argv, **kwargs):
    return subprocess.run(argv, check=True, timeout=120, text=True, capture_output=True, **kwargs)


def test_repaired_project_and_pipeline_behavior():
    assert os.path.isfile(os.path.join(REPO, "Cargo.toml"))
    assert os.path.isfile(os.path.join(REPO, "src/main.rs"))
    assert os.path.isfile(PROCESS_SCRIPT), f"{PROCESS_SCRIPT} is missing"
    assert stat.S_ISREG(os.stat(PROCESS_SCRIPT).st_mode), f"{PROCESS_SCRIPT} must be a regular file"
    assert os.access(PROCESS_SCRIPT, os.X_OK), f"{PROCESS_SCRIPT} is not executable"

    # Rebuild from the submitted Rust sources so a stale or fabricated binary cannot pass.
    run_checked(["cargo", "clean"], cwd=REPO)
    run_checked(["cargo", "build"], cwd=REPO)
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Cargo did not produce data_parser"

    nonce = secrets.token_hex(10)

    # Exercise the rebuilt parser directly on previously unknown nested input.
    direct_input = os.path.join(tempfile.gettempdir(), f"parser input {nonce}.txt")
    direct_leaf = f"leaf_{nonce}"
    with open(direct_input, "w") as f:
        f.write(f"  [NODE: [NODE: [NODE: {direct_leaf}]]]  \n")
    open(OUTPUT_LOG, "w").close()
    run_checked([BINARY, direct_input])
    with open(OUTPUT_LOG) as f:
        direct_lines = f.read().splitlines()
    assert direct_lines == [f"PROCESSED: {direct_leaf} WITH {TOKEN}"], \
        "The rebuilt Rust parser did not recursively unwrap the dynamic nested input"

    # Use an isolated, verifier-generated incoming directory so fixed expected strings
    # cannot satisfy the shell-script checks.
    backup_incoming = f"{INCOMING}.verifier-backup-{nonce}"
    os.rename(INCOMING, backup_incoming)
    os.mkdir(INCOMING)
    cases = {
        f"daily dump {nonce} one.txt": f"leaf_space_{nonce}",
        f"daily dump {nonce} two.txt": f"leaf_double_{nonce}",
        f"plain_{nonce}.txt": f"leaf_plain_{nonce}",
    }
    contents = {
        list(cases)[0]: f"[NODE: {cases[list(cases)[0]]}]\n",
        list(cases)[1]: f"[NODE: [NODE: {cases[list(cases)[1]]}]]\n",
        list(cases)[2]: f"[NODE: [NODE: [NODE: {cases[list(cases)[2]]}]]]\n",
    }
    for name, content in contents.items():
        with open(os.path.join(INCOMING, name), "w") as f:
            f.write(content)

    binary_backup = f"{BINARY}.verifier-real-{nonce}"
    capture = f"/tmp/data-parser-argv-{nonce}.jsonl"
    try:
        # Temporarily instrument the exact binary path to verify that process_all.sh
        # passes every filename, including spaces, as one complete argument.
        os.rename(BINARY, binary_backup)
        probe = f'''#!/usr/bin/python3
import json, os, sys
with open({capture!r}, "a") as out:
    out.write(json.dumps(sys.argv[1:]) + "\\n")
'''
        with open(BINARY, "w") as f:
            f.write(probe)
        os.chmod(BINARY, 0o755)
        run_checked([PROCESS_SCRIPT])
        with open(capture) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        expected_args = [[os.path.join(INCOMING, name)] for name in cases]
        assert collections.Counter(tuple(x) for x in calls) == collections.Counter(tuple(x) for x in expected_args), \
            "process_all.sh did not invoke data_parser once per file with each full filename as one argument"

        os.unlink(BINARY)
        os.rename(binary_backup, BINARY)

        # Run the actual rebuilt binary through the submitted script and validate all
        # dynamically derived outputs, not merely the two setup constants.
        open(OUTPUT_LOG, "w").close()
        run_checked([PROCESS_SCRIPT])
        with open(OUTPUT_LOG) as f:
            actual = f.read().splitlines()
        expected = [f"PROCESSED: {leaf} WITH {TOKEN}" for leaf in cases.values()]
        assert collections.Counter(actual) == collections.Counter(expected), \
            "The repaired pipeline did not produce exactly the expected dynamic outputs"
    finally:
        if os.path.exists(BINARY) and os.path.exists(binary_backup):
            os.unlink(BINARY)
        if os.path.exists(binary_backup):
            os.rename(binary_backup, BINARY)
        shutil.rmtree(INCOMING, ignore_errors=True)
        if os.path.exists(backup_incoming):
            os.rename(backup_incoming, INCOMING)
        if os.path.exists(direct_input):
            os.unlink(direct_input)
        if os.path.exists(capture):
            os.unlink(capture)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
