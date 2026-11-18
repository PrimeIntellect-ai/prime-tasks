#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

HOOK = Path("/home/user/uptime.git/hooks/post-receive")
SOURCE = Path("/home/user/post_receive.cpp")
HEARTBEAT = Path("/home/user/workspace/heartbeat.log")
FSTAB = Path("/home/user/fstab.mock")


def run_hook(executable):
    try:
        subprocess.run(
            [str(executable)], input="", check=True, capture_output=True,
            text=True, timeout=10
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Executing {executable} failed with exit code {e.returncode}. "
            f"Stderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Executing {executable} timed out")


def test_post_receive_exists_and_executable():
    assert HOOK.is_file(), f"The git hook binary {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"The git hook binary {HOOK} is not executable."
    with HOOK.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "The post-receive hook is not a compiled binary."


def test_cpp_source_exists_and_compiles(tmp_path):
    assert SOURCE.is_file(), f"The C++ source file {SOURCE} does not exist."
    rebuilt = tmp_path / "post-receive-rebuilt"
    result = subprocess.run(
        ["g++", "-std=c++17", str(SOURCE), "-o", str(rebuilt)],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"The C++ source does not compile: {result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)


def test_post_receive_logic():
    output_path = Path("/home/user/reports_dir/latest.txt")
    if output_path.exists():
        output_path.unlink()

    run_hook(HOOK)

    assert output_path.is_file(), f"The hook did not create the expected output file at {output_path}."
    content = output_path.read_text().strip()
    assert content == "Uptime: 80%", f"Expected 'Uptime: 80%', but found '{content}' in {output_path}."


def exercise_config_driven_behavior(executable, base):
    for case_number in range(4):
        mountpoint = base / f"mount-{case_number}-{secrets.token_hex(5)}"
        mountpoint.mkdir()

        total = 3 + secrets.randbelow(14)
        up_count = secrets.randbelow(total + 1)
        statuses = ["UP"] * up_count + ["DOWN"] * (total - up_count)
        # Randomize order without relying on a fixed fixture.
        for i in range(len(statuses) - 1, 0, -1):
            j = secrets.randbelow(i + 1)
            statuses[i], statuses[j] = statuses[j], statuses[i]
        start = 1800000000 + secrets.randbelow(1000000)
        HEARTBEAT.write_text("".join(f"{start + i * 37} {status}\n" for i, status in enumerate(statuses)))

        FSTAB.write_text(
            "# generated fstab fixture\n"
            "proc /proc proc defaults 0 0\n"
            f"/dev/mapper/other {base}/decoy ext4 defaults 0 2\n"
            f"/dev/mapper/uptime_data {mountpoint} ext4 defaults 0 2\n"
            "tmpfs /tmp tmpfs defaults 0 0\n"
        )
        output = mountpoint / "latest.txt"
        run_hook(executable)
        assert output.is_file(), f"{executable} ignored the configured mountpoint {mountpoint}"
        expected = f"Uptime: {(up_count * 100) // total}%"
        actual = output.read_text().strip()
        assert actual == expected, f"Expected {expected!r} from generated heartbeat data, got {actual!r}"


def test_hook_and_cpp_source_use_configuration_and_calculate_uptime(tmp_path):
    original_heartbeat = HEARTBEAT.read_bytes()
    original_fstab = FSTAB.read_bytes()
    try:
        exercise_config_driven_behavior(HOOK, tmp_path / "installed")

        rebuilt_dir = tmp_path / "rebuilt-tests"
        rebuilt_dir.mkdir()
        rebuilt = rebuilt_dir / "post-receive"
        result = subprocess.run(
            ["g++", "-std=c++17", str(SOURCE), "-o", str(rebuilt)],
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"The C++ source does not compile: {result.stderr}"
        source_cases = tmp_path / "source"
        source_cases.mkdir()
        exercise_config_driven_behavior(rebuilt, source_cases)
    finally:
        HEARTBEAT.write_bytes(original_heartbeat)
        FSTAB.write_bytes(original_fstab)


def test_setup_tunnel_script(tmp_path):
    script_path = Path("/home/user/setup_tunnel.sh")
    assert script_path.is_file(), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    content = script_path.read_text()
    expected_command = "ssh -N -f -L 9999:localhost:8000 user@localhost"
    assert expected_command in content, f"The script {script_path} does not contain the correct SSH port forwarding command."

    fake_bin = tmp_path / f"bin-{secrets.token_hex(6)}"
    fake_bin.mkdir()
    capture = tmp_path / f"ssh-calls-{secrets.token_hex(6)}"
    fake_ssh = fake_bin / "ssh"
    fake_ssh.write_text(
        "#!/bin/sh\n"
        "{ printf 'CALL\\n'; printf '%s\\n' \"$@\"; } >> \"$SSH_CAPTURE\"\n"
    )
    fake_ssh.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")
    env["SSH_CAPTURE"] = str(capture)
    result = subprocess.run(
        [str(script_path)], env=env, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Tunnel setup script failed: {result.stderr}"
    assert capture.is_file(), "The tunnel setup script did not execute ssh."
    assert capture.read_text().splitlines() == [
        "CALL", "-N", "-f", "-L", "9999:localhost:8000", "user@localhost"
    ], "The tunnel setup script did not invoke ssh with the required arguments."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
