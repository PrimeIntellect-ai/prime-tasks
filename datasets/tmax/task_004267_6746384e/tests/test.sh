#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import shutil
import signal
import stat
import subprocess
import tempfile
import time

import pytest


def run_classifier(path):
    return subprocess.run(
        ["/home/user/classifier", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def test_analyzer_exists_and_generates_crash_frame():
    source = "/home/user/analyze_frames.cpp"
    binary = "/home/user/analyze_frames"
    output = "/home/user/crash_frame.txt"

    assert os.path.isfile(source), f"Missing C++ source at {source}"
    assert os.path.getsize(source) > 0, f"Empty C++ source at {source}"
    assert os.path.isfile(binary), f"Missing compiled analyzer at {binary}"
    assert os.access(binary, os.X_OK), f"Analyzer at {binary} is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Analyzer at {binary} is not a compiled native executable"

    if os.path.exists(output):
        os.unlink(output)
    result = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Analyzer exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(output), f"Analyzer did not create {output}"

    with open(output, "r") as f:
        content = f.read().strip()
    assert content == "42", f"Expected '42' in {output}, but found '{content}'"


def test_classifier_executable_exists():
    source = "/home/user/classifier.cpp"
    path = "/home/user/classifier"
    assert os.path.isfile(source), f"Missing classifier source at {source}"
    assert os.path.getsize(source) > 0, f"Empty classifier source at {source}"
    assert os.path.isfile(path), f"Missing classifier program at {path}"
    assert os.access(path, os.X_OK), f"Classifier program at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Classifier at {path} is not a compiled native executable"


def test_classifier_clean_corpus():
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    assert len(clean_files) > 0, f"No files found in {clean_dir}"
    failed = [os.path.basename(p) for p in clean_files if run_classifier(p) != 0]
    if failed:
        pytest.fail(f"{len(failed)} of {len(clean_files)} clean files rejected: {', '.join(failed)}")


def test_classifier_evil_corpus():
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    assert len(evil_files) > 0, f"No files found in {evil_dir}"
    failed = [os.path.basename(p) for p in evil_files if run_classifier(p) != 1]
    if failed:
        pytest.fail(f"{len(failed)} of {len(evil_files)} evil files bypassed: {', '.join(failed)}")


def test_classifier_generated_adversarial_logs(tmp_path):
    rng = random.SystemRandom()
    cases = []

    for i in range(12):
        day = rng.randint(10, 28)
        hour = rng.randint(0, 23)
        minute = rng.randint(0, 59)
        second = rng.randint(0, 57)
        ts = f"Nov {day:02d} {hour:02d}:{minute:02d}:{second:02d}"
        later = f"Nov {day:02d} {hour:02d}:{minute:02d}:{second + 1:02d}"
        pid1 = rng.randint(1000, 60000)
        pid2 = rng.randint(1000, 60000)
        user = f"u{rng.randrange(10**9):09d}"
        host = f"host{rng.randrange(10**8):08d}"
        nonce = rng.randrange(10**12)
        accepted = f"{ts} {host} sshd[{pid1}]: Accepted publickey for {user} from 192.0.2.{i+1} port {30000+i}\n"
        closed = f"{ts} {host} sshd[{pid2}]: Connection closed by authenticating user {user} 192.0.2.{i+1} port {30000+i}\n"
        closed_later = f"{later} {host} sshd[{pid2}]: Connection closed by authenticating user {user} 192.0.2.{i+1} port {30000+i}\n"
        filler = f"{ts} {host} systemd[{pid1}]: randomized message {nonce}\n"

        cases.extend([
            (accepted + closed, 1),
            (accepted + filler + closed, 1),
            (filler + accepted + closed, 1),
            (accepted + closed_later, 0),
            (closed + accepted, 0),
            (accepted + filler, 0),
            (f"{ts} {host} auditd[{pid1}]: Accepted publickey for {user}\n" + closed, 0),
            (accepted + f"{ts} {host} auditd[{pid2}]: Connection closed by authenticating user {user}\n", 0),
            (f"{ts} {host} sshd[{pid1}]: Accepted publickey then Connection closed by authenticating user {user}\n", 0),
        ])

    rng.shuffle(cases)
    failures = []
    for index, (content, expected) in enumerate(cases):
        name = f"sample_{rng.randrange(10**18):018d}_{index}.dat"
        path = tmp_path / name
        path.write_text(content)
        actual = run_classifier(str(path))
        if actual != expected:
            failures.append((index, expected, actual, content))
    assert not failures, f"Generated classifier cases failed: {failures[:3]}"


def test_supervisor_script_exists_and_supervises():
    supervisor = "/home/user/supervisor.sh"
    mock = "/app/mock_qemu.sh"
    supervisor_log = "/home/user/supervisor.log"
    starts_file = "/tmp/verifier_qemu_starts"

    assert os.path.isfile(supervisor), f"Missing supervisor script at {supervisor}"
    assert os.access(supervisor, os.X_OK), f"Supervisor script at {supervisor} is not executable"

    with open(mock, "rb") as f:
        original_mock = f.read()
    original_mode = stat.S_IMODE(os.stat(mock).st_mode)

    for path in (supervisor_log, starts_file):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    test_mock = """#!/bin/bash
printf '%s %s\\n' "$(date +%s.%N)" "$$" >> /tmp/verifier_qemu_starts
sleep 0.20
exit 7
"""
    proc = None
    try:
        with open(mock, "w") as f:
            f.write(test_mock)
        os.chmod(mock, 0o755)

        proc = subprocess.Popen(
            [supervisor], cwd="/home/user",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.monotonic() + 6
        starts = []
        while time.monotonic() < deadline:
            if os.path.isfile(starts_file):
                with open(starts_file) as f:
                    starts = [line.strip() for line in f if line.strip()]
            if len(starts) >= 3:
                time.sleep(0.35)
                break
            if proc.poll() is not None:
                break
            time.sleep(0.05)

        assert proc.poll() is None, "Supervisor exited instead of running indefinitely"
        assert len(starts) >= 3, f"QEMU was not restarted repeatedly; starts observed: {starts}"

        times = [float(line.split()[0]) for line in starts[:3]]
        for previous, current in zip(times, times[1:]):
            interval = current - previous
            assert interval >= 0.15, f"Supervisor launched overlapping QEMU processes ({interval:.3f}s apart)"
            assert interval <= 1.35, f"Supervisor did not restart QEMU within one second of failure ({interval:.3f}s between starts)"

        assert os.path.isfile(supervisor_log), f"Missing restart log at {supervisor_log}"
        with open(supervisor_log) as f:
            restart_lines = [line.strip() for line in f if "Restarted QEMU" in line]
        assert len(restart_lines) >= 2, f"Expected every restart to be logged, found: {restart_lines}"
        for line in restart_lines:
            prefix = line.split("Restarted QEMU", 1)[0]
            assert re.search(r"\d", prefix), f"Restart entry has no timestamp: {line}"
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=2)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        with open(mock, "wb") as f:
            f.write(original_mock)
        os.chmod(mock, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
