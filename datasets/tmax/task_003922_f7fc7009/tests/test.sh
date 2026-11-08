#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import secrets
import subprocess


def test_payload_bin():
    path = "/home/user/investigation/payload.bin"
    assert os.path.isfile(path), f"{path} does not exist. Did you run the compiled extractor?"

    with open(path, "rb") as f:
        content = f.read()

    expected_content = b"Secret_Payload_123!"
    assert content == expected_content, f"The content of {path} is incorrect. The timeline sorting or decryption might still be flawed."


def test_flag_txt():
    path = "/home/user/investigation/flag.txt"
    assert os.path.isfile(path), f"{path} does not exist. Did you save the SHA-256 hash?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_hash = hashlib.sha256(b"Secret_Payload_123!").hexdigest()
    assert content == expected_hash, f"The hash in {path} does not match the expected SHA-256 hash of the payload."


def test_extractor_builds_and_handles_unseen_timeline(tmp_path):
    workspace = "/home/user/investigation"
    executable = tmp_path / "extractor"

    build = subprocess.run(
        ["go", "build", "-o", str(executable), "."],
        cwd=workspace,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"extractor.go does not build successfully:\n{build.stderr}"
    assert executable.is_file(), "go build did not produce an extractor executable"
    assert os.access(executable, os.X_OK), "the built extractor is not executable"
    assert executable.read_bytes()[:4] == b"\x7fELF", "the built extractor is not a Linux executable"

    expected = b"Secret_dynamic_" + secrets.token_bytes(29)
    encrypted = bytes(value ^ 0x42 for value in expected)
    encoded = base64.b64encode(encrypted).decode("ascii")
    chunks = [encoded[i:i + 8] for i in range(0, len(encoded), 8)]

    chronological = [
        f"2025-07-14T12:{index + 1:02d}:00Z kernel: [MAL] payload={chunk}"
        for index, chunk in enumerate(chunks)
    ]
    # Deliberately place the chunks in reverse chronological order and mix in noise.
    lines = ["2025-07-14T12:00:00Z sshd: Accepted publickey for analyst"]
    lines.extend(reversed(chronological))
    lines.append("2025-07-14T12:59:00Z sshd: Disconnected from analyst")
    (tmp_path / "auth.log").write_text("\n".join(lines) + "\n", encoding="utf-8")

    run = subprocess.run(
        [str(executable)],
        cwd=tmp_path,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, f"the built extractor failed on a valid unseen log:\n{run.stderr}"

    generated = tmp_path / "payload.bin"
    assert generated.is_file(), "the built extractor did not create payload.bin"
    assert generated.read_bytes() == expected, "the extractor did not correctly sort, decode, and decrypt an unseen payload timeline"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
