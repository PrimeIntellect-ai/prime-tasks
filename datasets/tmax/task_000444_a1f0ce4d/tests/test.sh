#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile

PROJECT = "/home/user/rate_limiter"
EXE = os.path.join(PROJECT, "rate_limit_checker")
LOG = os.path.join(PROJECT, "requests.log")
EXPECTED = (
    "ALLOW 192.168.1.1 10\n"
    "ALLOW 192.168.1.1 12\n"
    "DENY 192.168.1.1 13\n"
    "ALLOW 10.0.0.1 14\n"
    "ALLOW 192.168.1.1 20\n"
    "ALLOW 10.0.0.1 15\n"
    "DENY 10.0.0.1 16\n"
)


def djb2(value):
    h = 5381
    for byte in value.encode():
        h = ((h * 33) + byte) & 0xffffffff
    return h


def reference_output(records):
    table = [None] * 1024
    output = []
    for ip, timestamp in records:
        slot = djb2(ip) % 1024
        record = table[slot]
        if record is None or record[0] != ip:
            table[slot] = [ip, timestamp, 1]
            decision = "ALLOW"
        elif timestamp - record[1] < 5:
            record[2] += 1
            decision = "ALLOW" if record[2] <= 2 else "DENY"
        else:
            record[1] = timestamp
            record[2] = 1
            decision = "ALLOW"
        output.append(f"{decision} {ip} {timestamp}\n")
    return "".join(output)


def test_00_makefile_performs_a_clean_link():
    for name in ("rate_limit_checker", "main.o", "hash.o"):
        path = os.path.join(PROJECT, name)
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["make"], cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        "A clean make failed.\nSTDOUT:\n" + result.stdout + "\nSTDERR:\n" + result.stderr
    )
    assert os.path.isfile(os.path.join(PROJECT, "main.o")), "make did not build main.o"
    assert os.path.isfile(os.path.join(PROJECT, "hash.o")), "make did not build hash.o"
    assert os.path.isfile(EXE), "make did not produce rate_limit_checker"
    assert os.access(EXE, os.X_OK), "rate_limit_checker is not executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "rate_limit_checker is not an ELF executable"

    symbols = subprocess.run(
        ["nm", EXE], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"^[0-9a-fA-F]+\s+[Tt]\s+string_hash$", symbols, re.MULTILINE), (
        "The linked executable does not contain the assembly string_hash symbol"
    )


def test_executable_exists_and_runs():
    exe_path = "/home/user/rate_limiter/rate_limit_checker"
    assert os.path.isfile(exe_path), f"Executable {exe_path} is missing. Did you run make?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    log_path = "/home/user/rate_limiter/requests.log"
    result = subprocess.run([exe_path, log_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {exe_path} failed with return code {result.returncode}."
    assert result.stdout == EXPECTED, f"Output of {exe_path} does not match expected rate limiting logic."


def test_executable_handles_independently_generated_logs():
    rng = random.Random(947231)
    ips = [f"172.{rng.randrange(1, 250)}.{rng.randrange(256)}.{rng.randrange(1, 255)}" for _ in range(18)]

    # Include two different strings mapping to the same table slot to exercise
    # the actual assembly hash and the program's collision behavior.
    by_slot = {}
    collision = None
    for i in range(10000):
        candidate = f"10.{i // 65025}.{(i // 255) % 255}.{i % 255}"
        slot = djb2(candidate) % 1024
        if slot in by_slot and by_slot[slot] != candidate:
            collision = (by_slot[slot], candidate)
            break
        by_slot[slot] = candidate
    assert collision is not None
    ips.extend(collision)

    records = []
    current_time = 100
    for _ in range(140):
        current_time += rng.choice([0, 1, 2, 3, 6, 9])
        records.append((rng.choice(ips), current_time))
    a, b = collision
    records.extend([(a, current_time + 1), (a, current_time + 2),
                    (a, current_time + 3), (b, current_time + 4),
                    (a, current_time + 5)])

    fd, path = tempfile.mkstemp(prefix="rate-limit-verifier-", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            for ip, timestamp in records:
                f.write(f"{ip} {timestamp}\n")
        result = subprocess.run([EXE, path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, "rate_limit_checker failed on a generated log"
        assert result.stderr == "", "rate_limit_checker unexpectedly wrote to stderr"
        assert result.stdout == reference_output(records), (
            "rate_limit_checker produced incorrect decisions for a generated log"
        )
    finally:
        os.unlink(path)


def test_results_txt():
    results_path = "/home/user/results.txt"
    assert os.path.isfile(results_path), f"Results file {results_path} is missing."
    with open(results_path, "r") as f:
        content = f.read()
    assert content == EXPECTED, f"Content of {results_path} does not match the expected output."


def test_bench_sh():
    bench_path = "/home/user/bench.sh"
    assert os.path.isfile(bench_path), f"Benchmark script {bench_path} is missing."

    st = os.stat(bench_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Benchmark script {bench_path} is not executable."

    with open(bench_path, "r") as f:
        content = f.read()

    assert "500" in content, f"Benchmark script {bench_path} does not seem to contain the number 500 for the loop."
    assert "rate_limit_checker" in content, f"Benchmark script {bench_path} does not call rate_limit_checker."
    assert "requests.log" in content, f"Benchmark script {bench_path} does not pass requests.log as argument."
    assert "> /dev/null" in content or ">/dev/null" in content, f"Benchmark script {bench_path} does not redirect output to /dev/null."

    real_exe = EXE + ".verifier-real"
    count_path = "/tmp/bench-invocation-count"
    lock_path = "/tmp/bench-invocation-lock"
    for path in (real_exe, count_path, lock_path):
        if os.path.lexists(path):
            os.remove(path)
    with open(count_path, "w") as f:
        f.write("0\n")

    os.replace(EXE, real_exe)
    try:
        wrapper = f'''#!/bin/bash
if [ "$#" -ne 1 ] || [ "$(readlink -f -- "$1")" != "{LOG}" ]; then
    exit 42
fi
exec 9>>"{lock_path}"
flock 9
n=$(cat "{count_path}")
printf '%s\\n' "$((n + 1))" > "{count_path}"
flock -u 9
printf 'VERIFIER_BENCH_OUTPUT_MARKER\\n'
'''
        with open(EXE, "w") as f:
            f.write(wrapper)
        os.chmod(EXE, 0o755)

        result = subprocess.run(
            [bench_path], cwd="/home/user", capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            f"bench.sh failed with return code {result.returncode}: {result.stderr}"
        )
        with open(count_path) as f:
            count = int(f.read().strip())
        assert count == 500, f"bench.sh invoked rate_limit_checker {count} times instead of exactly 500"
        assert "VERIFIER_BENCH_OUTPUT_MARKER" not in result.stdout, (
            "bench.sh did not redirect rate_limit_checker standard output to /dev/null"
        )
    finally:
        if os.path.lexists(EXE):
            os.remove(EXE)
        os.replace(real_exe, EXE)
        for path in (count_path, lock_path):
            if os.path.lexists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
