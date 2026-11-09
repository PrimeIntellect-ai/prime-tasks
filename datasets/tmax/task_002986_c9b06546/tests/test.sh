#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess

SCRIPT_PATH = "/home/user/process.sh"
OUTPUT_PATH = "/home/user/unique_hashes.txt"
CONFIG_DIR = "/home/user/configs"


def read_hashes():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_process_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_unique_hashes_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."


def test_unique_hashes_content():
    payloads = [
        "server_name=app1\ntimeout=30\n",
        "server_name=app3\ntimeout=120\nmax_conn=500\n",
        "server_name=app_legacy\ndb_host=10.0.0.5\n",
    ]
    expected_hashes = sorted(
        hashlib.md5(p.encode("utf-8")).hexdigest() for p in payloads
    )
    actual_lines = read_hashes()
    assert actual_lines == expected_hashes, (
        f"The contents of {OUTPUT_PATH} do not match the expected unique hashes.\n"
        f"Expected: {expected_hashes}\n"
        f"Actual: {actual_lines}"
    )


def test_script_executes_on_original_fixture():
    os.remove(OUTPUT_PATH)
    run_script()

    payloads = [
        "server_name=app1\ntimeout=30\n",
        "server_name=app3\ntimeout=120\nmax_conn=500\n",
        "server_name=app_legacy\ndb_host=10.0.0.5\n",
    ]
    expected_hashes = sorted(
        hashlib.md5(p.encode("utf-8")).hexdigest() for p in payloads
    )
    assert read_hashes() == expected_hashes


def test_script_processes_unseen_mixed_encoding_fixture():
    nonce = secrets.token_hex(12)
    payload_a = f"service={nonce}\ntimeout=17\n"
    payload_b = f"name=café-{nonce}\nmode=安全\n"
    payload_c = f"first={nonce}\n\nlast=line\n"
    inactive_payload = f"inactive={nonce}\n"
    malformed_state_payload = f"wrong-state={nonce}\n"

    utf8_text = (
        "STATE: ACTIVE\n<PAYLOAD>\n" + payload_a + "</PAYLOAD>\n"
        "---\n"
        "STATE: INACTIVE\n<PAYLOAD>\n" + inactive_payload + "</PAYLOAD>\n"
        "---\n"
        "STATE: ACTIVE\n<PAYLOAD>\n" + payload_c + "</PAYLOAD>\n"
        "---\n"
        "STATE: ACTIVE \n<PAYLOAD>\n" + malformed_state_payload + "</PAYLOAD>\n"
    )
    utf16_text = (
        "STATE: ACTIVE\n<PAYLOAD>\n" + payload_a + "</PAYLOAD>\n"
        "---\n"
        "metadata=yes\nSTATE: ACTIVE\n<PAYLOAD>\n" + payload_b + "</PAYLOAD>\n"
        "---\n"
        "STATE: INACTIVE\n<PAYLOAD>\nignored=utf16\n</PAYLOAD>\n"
    )

    shutil.rmtree(CONFIG_DIR)
    os.makedirs(CONFIG_DIR)
    with open(os.path.join(CONFIG_DIR, "dynamic.utf8.txt"), "wb") as f:
        f.write(utf8_text.encode("utf-8"))
    with open(os.path.join(CONFIG_DIR, "dynamic.utf16.txt"), "wb") as f:
        f.write(utf16_text.encode("utf-16le"))

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_script()

    expected_hashes = sorted({
        hashlib.md5(payload_a.encode("utf-8")).hexdigest(),
        hashlib.md5(payload_b.encode("utf-8")).hexdigest(),
        hashlib.md5(payload_c.encode("utf-8")).hexdigest(),
    })
    actual_lines = read_hashes()
    assert actual_lines == expected_hashes, (
        "The script failed on an unseen mixed UTF-8/UTF-16LE fixture, or did not "
        "correctly validate, extract, deduplicate, hash, and sort its payloads.\n"
        f"Expected: {expected_hashes}\nActual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
