#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess


def test_compile_run_and_authenticate():
    forge_file = "/home/user/forge.c"
    forge_bin = "/tmp/forge_verified"
    payload_file = "/home/user/payload.bin"
    log_file = "/home/user/success.log"

    assert os.path.exists(forge_file), f"The file {forge_file} does not exist."
    assert os.path.isfile(forge_file), f"{forge_file} is not a file."

    if os.path.exists(forge_bin):
        os.remove(forge_bin)
    if os.path.exists(payload_file):
        os.remove(payload_file)

    compiled = subprocess.run(
        ["gcc", forge_file, "-o", forge_bin],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f"forge.c failed to compile:\n{compiled.stderr}"
    assert os.path.isfile(forge_bin), "Compiling forge.c did not produce an executable."

    generated = subprocess.run(
        [forge_bin],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert generated.returncode == 0, (
        f"The compiled forge program exited with status {generated.returncode}.\n"
        f"stderr: {generated.stderr.decode(errors='replace')}"
    )
    assert os.path.exists(payload_file), "Running the compiled forge program did not create /home/user/payload.bin."
    assert os.path.isfile(payload_file), f"{payload_file} is not a file."
    assert os.path.getsize(payload_file) == 32, f"The generated payload must be exactly 32 bytes."

    if os.path.exists(log_file):
        os.remove(log_file)

    authenticated = subprocess.run(
        ["/home/user/auth_bin", payload_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert authenticated.returncode == 0, (
        f"auth_bin rejected the generated payload with status {authenticated.returncode}.\n"
        f"stdout: {authenticated.stdout}\nstderr: {authenticated.stderr}"
    )
    assert "Access Granted: sysadmin" in authenticated.stdout, (
        "auth_bin did not print the expected successful authentication message."
    )
    assert os.path.isfile(log_file), "auth_bin did not create /home/user/success.log."


def test_key_found():
    key_file = "/home/user/key_found.txt"
    assert os.path.exists(key_file), f"The file {key_file} does not exist."
    assert os.path.isfile(key_file), f"{key_file} is not a file."

    with open(key_file, "r") as f:
        content = f.read()

    assert "XorEvasionKey99!" in content, f"The extracted key was not found in {key_file}."


def test_forge_c_exists():
    forge_file = "/home/user/forge.c"
    assert os.path.exists(forge_file), f"The file {forge_file} does not exist."
    assert os.path.isfile(forge_file), f"{forge_file} is not a file."


def test_payload_bin_size():
    payload_file = "/home/user/payload.bin"
    assert os.path.exists(payload_file), f"The file {payload_file} does not exist."
    assert os.path.isfile(payload_file), f"{payload_file} is not a file."

    size = os.path.getsize(payload_file)
    assert size == 32, f"The payload file {payload_file} is {size} bytes long, but must be exactly 32 bytes."


def test_success_log():
    log_file = "/home/user/success.log"
    assert os.path.exists(log_file), f"The file {log_file} does not exist. The payload may not have been executed successfully."
    assert os.path.isfile(log_file), f"{log_file} is not a file."

    with open(log_file, "r") as f:
        content = f.read()

    assert "sysadmin logged in" in content, f"The success log {log_file} does not contain the expected success message."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
