#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess


def read_guardian_multiplier():
    pidfile = "/home/user/.config_guardian.pid"
    assert os.path.isfile(pidfile), "The multiplier guardian PID file is missing."
    with open(pidfile, "r") as f:
        pid = int(f.read().strip())

    fd_dir = f"/proc/{pid}/fd"
    assert os.path.isdir(fd_dir), "The multiplier guardian process is no longer running."
    for entry in os.listdir(fd_dir):
        path = os.path.join(fd_dir, entry)
        try:
            target = os.readlink(path)
        except OSError:
            continue
        if target == "/home/user/config_multiplier.txt (deleted)":
            with open(path, "r") as f:
                return f.read().strip()
    raise AssertionError("Could not find the guardian's deleted config_multiplier.txt descriptor.")


def test_recovered_multiplier():
    expected = read_guardian_multiplier()
    filepath = "/home/user/recovered_multiplier.txt"
    assert os.path.isfile(filepath), f"The file {filepath} was not created."
    with open(filepath, "r") as f:
        content = f.read().strip()
    assert content == expected, f"Expected recovered multiplier to be '{expected}', but got '{content}'."


def test_ticket_resolution():
    multiplier = read_guardian_multiplier()
    expected_last = str(49 + (int(multiplier) % 25))

    filepath = "/home/user/ticket_resolution.txt"
    assert os.path.isfile(filepath), f"The file {filepath} was not created."
    with open(filepath, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {filepath}, but found {len(lines)}."
    assert lines[0] == multiplier, f"Expected line 1 to be '{multiplier}', but got '{lines[0]}'."
    assert lines[1] == expected_last, f"Expected line 2 to be '{expected_last}', but got '{lines[1]}'."


def test_process_killed():
    try:
        output = subprocess.check_output(["pgrep", "-f", "sequence_worker.py"], text=True)
        assert output.strip() == "", "The sequence_worker.py process is still running. It should have been killed."
    except subprocess.CalledProcessError:
        pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
