#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import errno
import os
import pty
import select
import subprocess
import time
import uuid
from pathlib import Path

import pytest


def test_add_user_mount_script():
    """Verify that the provisioning script exists and is executable."""
    script_path = "/home/user/add_user_mount.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_custom_fstab_contents():
    """Verify that custom_fstab contains the correct entries."""
    fstab_path = "/home/user/custom_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, 'r') as f:
        content = f.read()

    expected_lines = [
        "alice /mnt/alice_data ext4 defaults 0 0",
        "bob /mnt/bob_data xfs defaults 0 0",
        "charlie /mnt/charlie_data ext4 defaults 0 0"
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {fstab_path}."


def test_fstab_parser_c_exists():
    """Verify that the C source file exists."""
    c_file_path = "/home/user/fstab_parser.c"
    assert os.path.isfile(c_file_path), f"C source file {c_file_path} does not exist."


def test_fstab_parser_executable():
    """Verify that the compiled C executable exists and is executable."""
    exe_path = "/home/user/fstab_parser"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    # Optional: Check if it's an ELF file
    with open(exe_path, 'rb') as f:
        magic = f.read(4)
        assert magic == b'\x7fELF', f"File {exe_path} is not a valid ELF executable."


def test_fs_summary_log():
    """Verify that the summary log exists and has the correct sorted counts."""
    log_path = "/home/user/fs_summary.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ext4:2",
        "xfs:1"
    ]

    assert lines == expected_lines, f"Contents of {log_path} do not match the expected output. Got: {lines}"


def run_interactive_script(values):
    """Run the script on a pseudo-terminal and require each prompt in order."""
    prompts = [b"Username: ", b"Mountpoint: ", b"Filesystem: "]
    master, slave = pty.openpty()
    proc = None
    transcript = b""
    try:
        proc = subprocess.Popen(
            ["/home/user/add_user_mount.sh"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
        )
        os.close(slave)
        slave = None

        for prompt, value in zip(prompts, values):
            deadline = time.monotonic() + 5
            while prompt not in transcript:
                remaining = deadline - time.monotonic()
                assert remaining > 0, f"Did not receive exact prompt {prompt!r}; output was {transcript!r}"
                readable, _, _ = select.select([master], [], [], remaining)
                assert readable, f"Did not receive exact prompt {prompt!r}; output was {transcript!r}"
                try:
                    chunk = os.read(master, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        chunk = b""
                    else:
                        raise
                assert chunk, f"Script exited before prompt {prompt!r}; output was {transcript!r}"
                transcript += chunk
            os.write(master, value.encode() + b"\n")

        proc.wait(timeout=5)
        assert proc.returncode == 0, f"Provisioning script exited with {proc.returncode}; output was {transcript!r}"
        return transcript
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        if slave is not None:
            os.close(slave)
        os.close(master)


def test_add_user_mount_interactive_behavior():
    """Exercise exact prompts and dynamic appending behavior."""
    fstab = Path("/home/user/custom_fstab")
    original = fstab.read_bytes()
    token = uuid.uuid4().hex[:12]
    first = (f"verify_{token}_a", f"/mnt/verify_{token}_a", f"fs_{token}_a")
    second = (f"verify_{token}_b", f"/mnt/verify_{token}_b", f"fs_{token}_b")
    seed = b"# verifier-controlled input\n"

    try:
        fstab.write_bytes(seed)
        run_interactive_script(first)
        expected = seed + (" ".join(first) + " defaults 0 0\n").encode()
        assert fstab.read_bytes() == expected, "Script did not append the first supplied entry in exact fstab format."

        run_interactive_script(second)
        expected += (" ".join(second) + " defaults 0 0\n").encode()
        assert fstab.read_bytes() == expected, "Script did not append the second supplied entry in exact fstab format."
    finally:
        fstab.write_bytes(original)


def test_fstab_parser_on_dynamic_input():
    """Run the submitted ELF against altered input and derive expected counts."""
    fstab = Path("/home/user/custom_fstab")
    summary = Path("/home/user/fs_summary.log")
    original_fstab = fstab.read_bytes()
    original_summary = summary.read_bytes()
    token = uuid.uuid4().hex[:10]
    fstypes = [
        f"zeta_{token}",
        f"alpha_{token}",
        f"zeta_{token}",
        f"middle_{token}",
        f"alpha_{token}",
        f"zeta_{token}",
    ]
    controlled = "".join(
        f"device_{i}_{token} /mnt/check_{i}_{token} {fstype} defaults 0 0\n"
        for i, fstype in enumerate(fstypes)
    )
    expected = [
        f"alpha_{token}:2",
        f"middle_{token}:1",
        f"zeta_{token}:3",
    ]

    try:
        fstab.write_text(controlled)
        summary.write_text("decoy:999\n")
        result = subprocess.run(
            ["/home/user/fstab_parser"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"fstab_parser exited with {result.returncode}; "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert summary.is_file(), "fstab_parser did not create /home/user/fs_summary.log."
        actual = [line.strip() for line in summary.read_text().splitlines() if line.strip()]
        assert actual == expected, f"Parser output for dynamic input was {actual}, expected {expected}."
    finally:
        fstab.write_bytes(original_fstab)
        summary.write_bytes(original_summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
