#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import subprocess
from decimal import Decimal

import pytest


def test_align_logs_executable_exists():
    path = "/home/user/align_logs"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_align_logs_source_and_binary_kind():
    source = "/home/user/align_logs.c"
    binary = "/home/user/align_logs"
    assert os.path.isfile(source), f"C source {source} does not exist."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable."


def test_run_pipeline_script_exists():
    path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."


def test_archived_logs_exist():
    archive_a = "/home/user/logs/archive/srv_a.log"
    archive_b = "/home/user/logs/archive/srv_b.log"
    assert os.path.isfile(archive_a), f"Archived log {archive_a} does not exist."
    assert os.path.isfile(archive_b), f"Archived log {archive_b} does not exist."


def test_original_logs_moved():
    orig_a = "/home/user/logs/srv_a.log"
    orig_b = "/home/user/logs/srv_b.log"
    assert not os.path.isfile(orig_a), f"Original log {orig_a} was not moved."
    assert not os.path.isfile(orig_b), f"Original log {orig_b} was not moved."


def test_aligned_csv_content():
    path = "/home/user/output/aligned.csv"
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = (
        "timestamp,cpu,mem\n"
        "20,50.00,125.00\n"
        "30,55.00,175.00\n"
        "40,60.25,220.00\n"
        "50,65.00,260.00"
    )

    assert content == expected, f"Content of {path} does not match the expected interpolated values."


def test_crontab_configured():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read crontab for 'user': {e.stderr}")

    expected_command = "/home/user/run_pipeline.sh"
    found = False
    for line in crontab_content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            if parts[0] == "15" and parts[1] == "*" and parts[2] == "*" and parts[3] == "*" and parts[4] == "*":
                if expected_command in line:
                    found = True
                    break

    assert found, "Crontab for 'user' does not contain the correct schedule (15 * * * *) for /home/user/run_pipeline.sh"


def _expected_csv(a_rows, b_rows):
    lines = ["timestamp,cpu,mem"]
    for timestamp, cpu in a_rows:
        if timestamp < b_rows[0][0] or timestamp > b_rows[-1][0]:
            continue

        memory = None
        for bt, bm in b_rows:
            if timestamp == bt:
                memory = bm
                break

        if memory is None:
            for index in range(len(b_rows) - 1):
                left_t, left_m = b_rows[index]
                right_t, right_m = b_rows[index + 1]
                if left_t < timestamp < right_t:
                    memory = left_m + (right_m - left_m) * Decimal(timestamp - left_t) / Decimal(right_t - left_t)
                    break

        assert memory is not None
        lines.append(f"{timestamp},{cpu:.2f},{memory:.2f}")
    return "\n".join(lines)


def _write_inputs(a_rows, b_rows):
    user = pwd.getpwnam("user")
    os.makedirs("/home/user/logs", exist_ok=True)
    os.makedirs("/home/user/logs/archive", exist_ok=True)
    os.makedirs("/home/user/output", exist_ok=True)
    for directory in ("/home/user/logs", "/home/user/logs/archive", "/home/user/output"):
        os.chmod(directory, 0o777)

    a_content = "timestamp,cpu_usage\n" + "".join(f"{t},{cpu:.2f}\n" for t, cpu in a_rows)
    b_content = "timestamp,mem_usage\n" + "".join(f"{t},{mem:.2f}\n" for t, mem in b_rows)
    for path, content in (("/home/user/logs/srv_a.log", a_content), ("/home/user/logs/srv_b.log", b_content)):
        with open(path, "w") as f:
            f.write(content)
        os.chown(path, user.pw_uid, user.pw_gid)
    return a_content, b_content


def _make_case():
    rng = secrets.SystemRandom()
    start = rng.randrange(1000, 9000)
    width1 = rng.choice([10, 14, 18, 22, 26])
    width2 = rng.choice([12, 16, 20, 24, 28])
    b_times = [start, start + width1, start + width1 + width2]
    b_rows = [
        (b_times[0], Decimal(rng.randrange(80, 180))),
        (b_times[1], Decimal(rng.randrange(210, 330))),
        (b_times[2], Decimal(rng.randrange(350, 480))),
    ]
    a_times = [
        start - rng.randrange(1, 8),
        start,
        start + width1 // 2,
        start + width1,
        start + width1 + width2 // 2,
        start + width1 + width2,
        start + width1 + width2 + rng.randrange(1, 8),
    ]
    a_rows = [(t, Decimal(35 + i * 7) + Decimal("0.25")) for i, t in enumerate(a_times)]
    return a_rows, b_rows


def _run_as_user(command):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=True,
    )


def test_executable_interpolates_new_inputs_and_pipeline_executes_it():
    # Exercise the compiled program directly on more than one unpredictable input.
    for _ in range(2):
        a_rows, b_rows = _make_case()
        _write_inputs(a_rows, b_rows)
        output = "/home/user/output/aligned.csv"
        if os.path.exists(output):
            os.unlink(output)
        _run_as_user(["/home/user/align_logs"])
        assert os.path.isfile(output), "align_logs did not create aligned.csv"
        with open(output) as f:
            actual = f.read().strip()
        assert actual == _expected_csv(a_rows, b_rows)
        assert os.path.isfile("/home/user/logs/srv_a.log"), "align_logs incorrectly moved srv_a.log"
        assert os.path.isfile("/home/user/logs/srv_b.log"), "align_logs incorrectly moved srv_b.log"

    # Instrument the required executable path, then run the pipeline itself.
    a_rows, b_rows = _make_case()
    a_content, b_content = _write_inputs(a_rows, b_rows)
    expected = _expected_csv(a_rows, b_rows)
    for path in ("/home/user/logs/archive/srv_a.log", "/home/user/logs/archive/srv_b.log", "/home/user/output/aligned.csv"):
        if os.path.exists(path):
            os.unlink(path)

    binary = "/home/user/align_logs"
    real_binary = "/home/user/align_logs.__verifier_real"
    marker = "/tmp/align_logs_pipeline_called"
    if os.path.exists(marker):
        os.unlink(marker)
    if os.path.exists(real_binary):
        os.unlink(real_binary)
    os.replace(binary, real_binary)
    try:
        with open(binary, "w") as f:
            f.write("#!/bin/bash\nprintf called > /tmp/align_logs_pipeline_called\nexec /home/user/align_logs.__verifier_real \"$@\"\n")
        os.chmod(binary, 0o755)
        user = pwd.getpwnam("user")
        os.chown(binary, user.pw_uid, user.pw_gid)

        _run_as_user(["/home/user/run_pipeline.sh"])

        assert os.path.isfile(marker), "run_pipeline.sh did not execute /home/user/align_logs"
        assert not os.path.exists("/home/user/logs/srv_a.log"), "Pipeline did not move srv_a.log"
        assert not os.path.exists("/home/user/logs/srv_b.log"), "Pipeline did not move srv_b.log"
        with open("/home/user/logs/archive/srv_a.log") as f:
            assert f.read() == a_content
        with open("/home/user/logs/archive/srv_b.log") as f:
            assert f.read() == b_content
        with open("/home/user/output/aligned.csv") as f:
            assert f.read().strip() == expected
    finally:
        if os.path.exists(real_binary):
            if os.path.exists(binary):
                os.unlink(binary)
            os.replace(real_binary, binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
