#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

V2_DIR = Path("/home/user/app/v2")
DISPATCHER = V2_DIR / "dispatcher"
SOURCE = Path("/home/user/workspace/dispatcher_v2.cpp")
SCRIPT = Path("/home/user/workspace/process_queue.sh")
LISTS = Path("/home/user/mail_queue/lists")
INCOMING = Path("/home/user/mail_queue/incoming")


def run_dispatcher(executable, args, email=b"", timeout=10):
    return subprocess.run(
        [str(executable), *args],
        input=email,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def assert_mode_755(path):
    mode = stat.S_IMODE(os.stat(path).st_mode)
    assert mode == 0o755, f"{path} has mode {oct(mode)}, expected 0o755"


def exercise_dispatcher(executable):
    token = secrets.token_hex(12)
    target = Path(f"/tmp/dispatcher-target-{token}.eml")
    target.write_text("These file contents must not be parsed.\n", encoding="utf-8")

    msg_angle = f"angle-{token}"
    angle_link = LISTS / "announce" / f"{msg_angle}.eml"
    angle_link.unlink(missing_ok=True)
    email = (
        "From: sender@localhost\n"
        "To: announce@localhost\n"
        f"Message-ID: <{msg_angle}>\n"
        "\nBody\n"
    ).encode()
    result = run_dispatcher(executable, [str(target)], email)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert angle_link.is_symlink(), f"Dispatcher did not create {angle_link}"
    assert os.readlink(angle_link) == str(target)

    msg_plain = f"plain-{token}"
    plain_link = LISTS / "discuss" / f"{msg_plain}.eml"
    plain_link.unlink(missing_ok=True)
    email = (
        "To: discuss@localhost\n"
        f"Message-ID: {msg_plain}\n"
        "\nBody\n"
    ).encode()
    result = run_dispatcher(executable, [str(target)], email)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert plain_link.is_symlink(), f"Dispatcher did not create {plain_link}"
    assert os.readlink(plain_link) == str(target)

    missing_to = run_dispatcher(
        executable,
        [str(target)],
        f"Message-ID: missing-to-{token}\n\nBody\n".encode(),
    )
    assert missing_to.returncode == 1, "Missing To header must produce exit code 1"

    missing_id = run_dispatcher(
        executable,
        [str(target)],
        b"To: announce@localhost\n\nBody\n",
    )
    assert missing_id.returncode == 1, "Missing Message-ID header must produce exit code 1"

    assert run_dispatcher(executable, [], b"").returncode != 0
    assert run_dispatcher(executable, [str(target), str(target)], b"").returncode != 0


def test_v2_directory_and_executable():
    v2_dir = "/home/user/app/v2"
    dispatcher_path = os.path.join(v2_dir, "dispatcher")

    assert os.path.isdir(v2_dir), f"Directory {v2_dir} does not exist."
    assert os.path.isfile(dispatcher_path), f"Dispatcher executable {dispatcher_path} does not exist."
    assert os.access(dispatcher_path, os.X_OK), f"Dispatcher {dispatcher_path} is not executable."
    with open(dispatcher_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The deployed dispatcher is not a compiled executable"
    assert_mode_755(v2_dir)


def test_cpp_source_compiles_and_works(tmp_path):
    assert SOURCE.is_file(), f"C++ source {SOURCE} does not exist"
    rebuilt = tmp_path / "dispatcher-from-source"
    result = subprocess.run(
        ["g++", str(SOURCE), "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    exercise_dispatcher(rebuilt)


def test_deployed_dispatcher_behavior():
    exercise_dispatcher(DISPATCHER)


def test_mailing_list_directories():
    announce_dir = "/home/user/mail_queue/lists/announce"
    discuss_dir = "/home/user/mail_queue/lists/discuss"

    assert os.path.isdir(announce_dir), f"Mailing list directory {announce_dir} does not exist."
    assert os.path.isdir(discuss_dir), f"Mailing list directory {discuss_dir} does not exist."
    assert_mode_755(announce_dir)
    assert_mode_755(discuss_dir)


def test_current_symlink_points_to_v2():
    current_symlink = "/home/user/app/current"

    assert os.path.islink(current_symlink), f"{current_symlink} is not a symlink."
    target = os.readlink(current_symlink)
    assert target == "/home/user/app/v2", f"Symlink {current_symlink} points to {target}, expected /home/user/app/v2."


def test_process_queue_script_executes_and_processes_all_files():
    script_path = "/home/user/workspace/process_queue.sh"

    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Bash script {script_path} is not executable."
    script_text = SCRIPT.read_text(encoding="utf-8")
    assert script_text.splitlines() and "bash" in script_text.splitlines()[0], "Queue script must be a bash script"
    assert "/home/user/app/current/dispatcher" in script_text, "Queue script must use the newly deployed dispatcher"

    expected_links = {
        LISTS / "announce" / "abc-123-xyz.eml": INCOMING / "msg1.eml",
        LISTS / "discuss" / "def-456-uvw.eml": INCOMING / "msg2.eml",
        LISTS / "discuss" / "789-ghi.eml": INCOMING / "msg3.eml",
    }

    token = secrets.token_hex(12)
    extra_file = INCOMING / f"verification-{token}.eml"
    extra_id = f"queue-{token}"
    extra_link = LISTS / "announce" / f"{extra_id}.eml"
    extra_file.write_text(
        "From: verifier@localhost\n"
        "To: announce@localhost\n"
        f"Message-ID: <{extra_id}>\n"
        "\nVerification message.\n",
        encoding="utf-8",
    )
    expected_links[extra_link] = extra_file

    for link in expected_links:
        link.unlink(missing_ok=True)

    try:
        result = subprocess.run(
            [script_path],
            cwd="/tmp",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        for link_path, expected_target in expected_links.items():
            assert link_path.is_symlink(), f"Expected symlink {link_path} was not created by the queue script."
            assert os.readlink(link_path) == str(expected_target), (
                f"Symlink {link_path} points to {os.readlink(link_path)}, expected {expected_target}."
            )
    finally:
        extra_file.unlink(missing_ok=True)
        extra_link.unlink(missing_ok=True)


def test_dispatcher_created_symlinks():
    expected_links = {
        "/home/user/mail_queue/lists/announce/abc-123-xyz.eml": "/home/user/mail_queue/incoming/msg1.eml",
        "/home/user/mail_queue/lists/discuss/def-456-uvw.eml": "/home/user/mail_queue/incoming/msg2.eml",
        "/home/user/mail_queue/lists/discuss/789-ghi.eml": "/home/user/mail_queue/incoming/msg3.eml"
    }

    for link_path, expected_target in expected_links.items():
        assert os.path.islink(link_path), f"Expected symlink {link_path} was not created."
        actual_target = os.readlink(link_path)
        assert actual_target == expected_target, f"Symlink {link_path} points to {actual_target}, expected {expected_target}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
