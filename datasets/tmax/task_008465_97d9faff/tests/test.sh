#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_edge_stack.py
import os
import random
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

EDGE_DIR = "/home/user/edge"
LOG_DIR = os.path.join(EDGE_DIR, "logs")


def run(cmd, *, cwd=None, timeout=30):
    return subprocess.run(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


def assert_elf(path):
    assert os.path.isfile(path), f"Compiled binary {path} is missing"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a valid ELF binary"


def test_01_original_static_assertions():
    sensor = os.path.join(EDGE_DIR, "sensor.go")
    assert os.path.isfile(sensor), f"{sensor} is missing"
    with open(sensor) as f:
        content = f.read()
    assert "127.0.0.1:9091" in content, f"Port in {sensor} was not updated to match collector.go (9091)"

    init = os.path.join(EDGE_DIR, "init.sh")
    assert os.path.isfile(init), f"{init} is missing"
    assert os.stat(init).st_mode & stat.S_IXUSR, f"{init} is not executable"

    process = os.path.join(EDGE_DIR, "process.sh")
    assert os.path.isfile(process), f"{process} is missing"
    assert os.stat(process).st_mode & stat.S_IXUSR, f"{process} is not executable"

    quota_source = os.path.join(EDGE_DIR, "quota.go")
    assert os.path.isfile(quota_source), f"{quota_source} is missing"

    for name in ["sensor", "collector", "quota"]:
        assert_elf(os.path.join(EDGE_DIR, "bin", name))


def test_02_original_final_state_assertions():
    old_log = os.path.join(LOG_DIR, "old_sys.log")
    recent_log = os.path.join(LOG_DIR, "recent_errors.log")
    assert not os.path.exists(old_log), f"{old_log} was not deleted by the quota enforcement"
    assert os.path.isfile(recent_log), f"{recent_log} should not have been deleted"

    summary = os.path.join(EDGE_DIR, "error_summary.txt")
    assert os.path.isfile(summary), f"{summary} is missing"
    with open(summary) as f:
        content = f.read().strip()
    expected = "401: 1\n404: 2\n502: 3"
    assert content == expected, (
        f"Contents of {summary} do not match the expected summary.\n"
        f"Expected:\n{expected}\nGot:\n{content}"
    )


def test_03_init_is_executable_idempotent_and_builds_sources():
    bin_dir = os.path.join(EDGE_DIR, "bin")
    sensor_bin = os.path.join(bin_dir, "sensor")
    collector_bin = os.path.join(bin_dir, "collector")

    os.remove(sensor_bin)
    os.remove(collector_bin)
    run(["./init.sh"], cwd=EDGE_DIR)
    assert_elf(sensor_bin)
    assert_elf(collector_bin)

    # A second invocation must also succeed and leave usable products.
    run(["./init.sh"], cwd=EDGE_DIR)
    assert_elf(sensor_bin)
    assert_elf(collector_bin)


def test_04_sensor_and_collector_really_communicate():
    collector = os.path.join(EDGE_DIR, "bin", "collector")
    sensor = os.path.join(EDGE_DIR, "bin", "sensor")
    proc = subprocess.Popen(
        [collector],
        cwd=EDGE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        time.sleep(0.35)
        sent = subprocess.run(
            [sensor], cwd=EDGE_DIR, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=5
        )
        assert sent.returncode == 0, f"sensor failed: {sent.stderr}"
        stdout, stderr = proc.communicate(timeout=5)
        assert proc.returncode == 0, f"collector failed: {stderr}"
        assert "telemetry data" in stdout, f"collector did not receive sensor telemetry; output was {stdout!r}"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate()


def exercise_quota(executable, delete_all=False):
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="quota-case-") as directory:
        names = [f"{uuid.uuid4().hex}.log" for _ in range(3)]
        sizes = [rng.randint(37, 83), rng.randint(89, 137), rng.randint(149, 211)]
        base = time.time() - 10000
        for index, (name, size) in enumerate(zip(names, sizes)):
            path = os.path.join(directory, name)
            with open(path, "wb") as f:
                f.write(os.urandom(size))
            os.utime(path, (base + index * 100, base + index * 100))

        unrelated = os.path.join(directory, "keep.data")
        with open(unrelated, "wb") as f:
            f.write(os.urandom(sum(sizes) + 500))

        if delete_all:
            limit = sizes[-1] - 1
            expected = set()
        else:
            # Correct behavior removes exactly the oldest file and stops at equality.
            limit = sizes[1] + sizes[2]
            expected = {names[1], names[2]}

        run([executable, directory, str(limit)], timeout=10)
        remaining = {name for name in os.listdir(directory) if name.endswith(".log")}
        assert remaining == expected, (
            f"quota retained the wrong files for limit {limit}: "
            f"expected {expected}, got {remaining}"
        )
        assert os.path.isfile(unrelated), "quota deleted a non-.log file"
        total = sum(os.path.getsize(os.path.join(directory, name)) for name in remaining)
        assert total <= limit, f"quota left {total} bytes, above limit {limit}"


def test_05_quota_binary_and_source_enforce_varied_quotas():
    submitted = os.path.join(EDGE_DIR, "bin", "quota")
    exercise_quota(submitted, delete_all=False)
    exercise_quota(submitted, delete_all=True)

    with tempfile.TemporaryDirectory(prefix="quota-build-") as directory:
        rebuilt = os.path.join(directory, "quota-from-source")
        run(["go", "build", "-o", rebuilt, os.path.join(EDGE_DIR, "quota.go")], cwd=EDGE_DIR, timeout=60)
        assert_elf(rebuilt)
        exercise_quota(rebuilt, delete_all=False)
        exercise_quota(rebuilt, delete_all=True)


def test_06_process_script_parses_current_varied_logs():
    process = os.path.join(EDGE_DIR, "process.sh")
    summary = os.path.join(EDGE_DIR, "error_summary.txt")
    backup_logs = os.path.join(EDGE_DIR, f"logs.verifier-backup-{uuid.uuid4().hex}")
    old_summary = open(summary, "rb").read() if os.path.exists(summary) else None

    rng = random.SystemRandom()
    codes = rng.sample(range(120, 899), 4)
    counts = {code: rng.randint(1, 5) for code in codes}

    os.rename(LOG_DIR, backup_logs)
    os.mkdir(LOG_DIR)
    try:
        lines_a = ["2026-01-01T00:00:00Z [INFO] Started"]
        lines_b = []
        serial = 0
        for code, count in counts.items():
            for _ in range(count):
                line = f"2026-01-01T00:00:{serial % 60:02d}Z [ERROR] Code {code}: generated failure"
                (lines_a if serial % 2 == 0 else lines_b).append(line)
                serial += 1
        rng.shuffle(lines_a)
        rng.shuffle(lines_b)
        with open(os.path.join(LOG_DIR, "alpha.log"), "w") as f:
            f.write("\n".join(lines_a) + "\n")
        with open(os.path.join(LOG_DIR, "beta.log"), "w") as f:
            f.write("\n".join(lines_b) + "\n")
        with open(os.path.join(LOG_DIR, "ignored.txt"), "w") as f:
            f.write("2026-01-01T00:00:00Z [ERROR] Code 999: must be ignored\n")

        run(["./process.sh"], cwd=EDGE_DIR, timeout=10)
        with open(summary) as f:
            actual = f.read().strip()
        expected = "\n".join(f"{code}: {counts[code]}" for code in sorted(counts))
        assert actual == expected, f"dynamic error summary mismatch; expected {expected!r}, got {actual!r}"
    finally:
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        os.rename(backup_logs, LOG_DIR)
        if old_summary is None:
            if os.path.exists(summary):
                os.remove(summary)
        else:
            with open(summary, "wb") as f:
                f.write(old_summary)

    # Execute the pipeline on the required final logs and retain the original assertion.
    run(["./process.sh"], cwd=EDGE_DIR, timeout=10)
    with open(summary) as f:
        actual = f.read().strip()
    expected = "401: 1\n404: 2\n502: 3"
    assert actual == expected, f"restored-log summary mismatch; expected {expected!r}, got {actual!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_edge_stack.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
