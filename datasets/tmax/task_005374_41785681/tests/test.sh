#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import secrets
import shutil
import stat
import subprocess
import time


def test_tracker_script_exists_and_executable():
    script_path = "/home/user/tracker.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_tracker_script_uses_flock():
    script_path = "/home/user/tracker.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "flock" in content, f"Script {script_path} does not use 'flock' as required."


def test_summary_log_contents():
    log_path = "/home/user/summary.log"
    assert os.path.isfile(log_path), f"Summary log {log_path} was not generated."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "a.bin: 1A2B3C4D",
        "d.bin: F5E6D7C8"
    }
    actual_lines = set(lines)

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."
    assert actual_lines == expected_lines, f"Contents of {log_path} do not match the expected output. Expected {expected_lines}, but got {actual_lines}."


def test_tracker_behavior_and_locking():
    script_path = "/home/user/tracker.sh"
    with open(script_path, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, "tracker.sh must be a Bash script."

    run_id = secrets.token_hex(6)
    configs = "/home/user/configs"
    binaries = "/home/user/binaries"
    external_dir = f"/home/user/config_target_{run_id}"

    shutil.rmtree(configs)
    os.makedirs(configs)
    os.makedirs(binaries, exist_ok=True)
    os.makedirs(external_dir)

    bin1_name = f"probe_{run_id}_one.bin"
    bin2_name = f"probe_{run_id}_two.bin"
    bin1 = os.path.join(binaries, bin1_name)
    bin2 = os.path.join(binaries, bin2_name)
    value1 = os.urandom(4)
    value2 = os.urandom(4)

    with open(bin1, "wb") as f:
        f.write(os.urandom(8) + value1 + os.urandom(9))
    with open(bin2, "wb") as f:
        f.write(os.urandom(8) + value2 + os.urandom(7))

    primary = os.path.join(configs, f"primary_{run_id}.ini")
    with open(primary, "w") as f:
        f.write(f"BinPath={bin1}\n")
    os.symlink(primary, os.path.join(configs, f"primary_alias_{run_id}.ini"))
    os.symlink(primary, os.path.join(configs, f"primary_alias2_{run_id}.ini"))

    secondary = os.path.join(external_dir, f"secondary_{run_id}.ini")
    with open(secondary, "w") as f:
        f.write(f"BinPath={bin2}\n")
    os.symlink(external_dir, os.path.join(configs, f"external_dir_{run_id}"))
    os.symlink(external_dir, os.path.join(configs, f"external_dir_alias_{run_id}"))

    # Both file and directory symlink loops must be skipped without hanging.
    os.symlink(os.path.join(configs, f"loop2_{run_id}.ini"), os.path.join(configs, f"loop1_{run_id}.ini"))
    os.symlink(os.path.join(configs, f"loop1_{run_id}.ini"), os.path.join(configs, f"loop2_{run_id}.ini"))
    os.symlink(configs, os.path.join(configs, f"directory_loop_{run_id}"))

    expected = sorted([
        f"{bin1_name}: {value1.hex().upper()}",
        f"{bin2_name}: {value2.hex().upper()}",
    ])

    def read_lines():
        assert os.path.isfile("/home/user/summary.log"), "tracker.sh did not generate summary.log"
        with open("/home/user/summary.log", "r") as f:
            return sorted(line.strip() for line in f if line.strip())

    # Execute the submitted artifact against verifier-generated data.
    open("/home/user/summary.log", "w").close()
    subprocess.run([script_path], check=True, timeout=10,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert read_lines() == expected, "tracker.sh produced incorrect output or processed a physical .ini file more than once"

    # Hold the required lock before execution. The script must block before any write.
    open("/home/user/summary.log", "w").close()
    lock_file = open("/home/user/summary.lock", "a+")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = subprocess.Popen([script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.75)
    blocked = proc.poll() is None
    with open("/home/user/summary.log", "r") as f:
        premature_output = f.read()
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()

    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise AssertionError("tracker.sh did not terminate after the lock was released")

    assert blocked, "tracker.sh did not wait for the exclusive summary.lock lock"
    assert premature_output == "", "tracker.sh wrote summary.log while another process held summary.lock"
    assert proc.returncode == 0, "tracker.sh failed after the lock was released"
    assert read_lines() == expected, "tracker.sh produced incorrect output after acquiring the lock"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
