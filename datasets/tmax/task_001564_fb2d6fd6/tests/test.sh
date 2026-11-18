#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import pwd
import secrets
import shutil
import subprocess
import tempfile
import time


def run_as_user(cmd):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(cmd, check=True, capture_output=True, text=True, preexec_fn=demote)


def run_detector(binary, output_file):
    if os.path.lexists(output_file):
        os.remove(output_file)
    start = time.perf_counter()
    result = run_as_user([binary])
    elapsed = time.perf_counter() - start
    assert os.path.isfile(output_file), f"{binary} did not produce {output_file}."
    with open(output_file, "r") as f:
        lines = f.read().splitlines()
    return lines, elapsed, result


def test_fast_detector_correctness_and_speedup():
    naive_src = "/app/naive.cpp"
    fast_src = "/home/user/fast_detector.cpp"
    fast_bin = "/home/user/fast_detector"
    verified_fast_bin = "/tmp/verified_fast_detector"
    output_file = "/home/user/deadlocks.txt"
    dataset = "/app/transactions.csv"

    # Preserve the original executable assertions.
    assert os.path.isfile(fast_bin), f"Executable {fast_bin} not found. Did you compile your program?"
    assert os.access(fast_bin, os.X_OK), f"File {fast_bin} is not executable."
    with open(fast_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{fast_bin} is not a compiled executable."

    # The requested C++ source must exist and independently compile.
    assert os.path.isfile(fast_src), f"C++ source {fast_src} not found."
    assert os.path.getsize(fast_src) > 0, f"C++ source {fast_src} is empty."
    with open(fast_src, "rb") as submitted, open(naive_src, "rb") as reference:
        assert submitted.read() != reference.read(), "Submitted source is byte-identical to the naive reference implementation."

    compile_fast = subprocess.run(
        ["g++", "-O3", "-std=c++17", fast_src, "-o", verified_fast_bin],
        capture_output=True, text=True
    )
    assert compile_fast.returncode == 0, f"Failed to compile {fast_src}: {compile_fast.stderr}"

    # Exercise both the submitted executable and a fresh build of its source on
    # unpredictable data before any reference answer is created.
    original_csv = open(dataset, "rb").read()
    token = secrets.token_hex(8).upper()
    a, b, c = [f"TX_{token}_{x}" for x in ("A", "B", "C")]
    d = f"TX_{token}_SELF"
    e, fnode = f"TX_{token}_E", f"TX_{token}_F"
    low1, low2 = f"TX_{token}_LOW1", f"TX_{token}_LOW2"
    maint1, maint2 = f"TX_{token}_M1", f"TX_{token}_M2"
    sysnode, normal = f"SYS_{token}", f"TX_{token}_NORMAL"
    tail1, tail2 = f"TX_{token}_TAIL1", f"TX_{token}_TAIL2"
    expected_challenge = sorted([a, b, c, d, e, fnode])

    rows = [
        (a, b, 15, "READ"), (b, c, 20, "WRITE"), (c, a, 50, "READ"),
        (d, d, 15, "WRITE"),
        (e, fnode, 30, "READ"), (fnode, e, 30, "WRITE"),
        (c, tail1, 20, "READ"), (tail1, tail2, 20, "READ"),
        (low1, low2, 14, "READ"), (low2, low1, 20, "READ"),
        (maint1, maint2, 25, "MAINT"), (maint2, maint1, 25, "READ"),
        (sysnode, normal, 25, "READ"), (normal, sysnode, 25, "READ"),
    ]

    challenge_results = []
    try:
        with open(dataset, "w", newline="") as out:
            writer = csv.writer(out)
            writer.writerow(["src_tx", "dst_tx", "wait_time_ms", "tx_type"])
            writer.writerows(rows)
        for binary in (fast_bin, verified_fast_bin):
            lines, _, _ = run_detector(binary, output_file)
            challenge_results.append((binary, lines))
    finally:
        with open(dataset, "wb") as out:
            out.write(original_csv)
        if os.path.lexists(output_file):
            os.remove(output_file)

    for binary, lines in challenge_results:
        assert lines == expected_challenge, (
            f"{binary} failed the dynamic filtering/cycle-detection test."
        )

    # Compile the original naive implementation, changing only its output path.
    # The answer is kept in a root-only directory and removed before either
    # submitted artifact is run, so it is never exposed at a readable path.
    secure_dir = tempfile.mkdtemp(prefix="deadlock_reference_")
    os.chmod(secure_dir, 0o700)
    naive_bin = os.path.join(secure_dir, "naive")
    naive_output = os.path.join(secure_dir, "answer.txt")
    patched_naive = os.path.join(secure_dir, "naive.cpp")
    try:
        with open(naive_src, "r") as f:
            naive_code = f.read()
        old_path = '"/home/user/deadlocks.txt"'
        assert old_path in naive_code, "Naive implementation has an unexpected output path."
        naive_code = naive_code.replace(old_path, '"' + naive_output + '"')
        with open(patched_naive, "w") as f:
            f.write(naive_code)

        compile_naive = subprocess.run(
            ["g++", "-O3", patched_naive, "-o", naive_bin],
            capture_output=True, text=True
        )
        assert compile_naive.returncode == 0, f"Failed to compile naive implementation: {compile_naive.stderr}"

        t0 = time.perf_counter()
        naive_run = subprocess.run([naive_bin], capture_output=True, text=True)
        naive_time = time.perf_counter() - t0
        assert naive_run.returncode == 0, f"Naive implementation failed to run: {naive_run.stderr}"
        assert os.path.isfile(naive_output), "Naive implementation did not produce its output."
        with open(naive_output, "r") as f:
            naive_lines = f.read().splitlines()
        os.remove(naive_output)

        # Preserve the original correctness and speed assertions for the
        # submitted executable, and apply them to a fresh source build too.
        for binary in (fast_bin, verified_fast_bin):
            fast_lines, fast_time, _ = run_detector(binary, output_file)
            assert len(fast_lines) > 0, "Your output file is empty."
            assert naive_lines == fast_lines, (
                f"The output of {binary} does not exactly match the reference output. "
                "Check your filtering rules and cycle detection."
            )
            speedup = naive_time / fast_time
            assert speedup >= 20.0, (
                f"Speedup for {binary} is {speedup:.2f}x "
                f"(Naive: {naive_time:.4f}s, Yours: {fast_time:.4f}s), "
                "which is less than the required 20.0x threshold."
            )
    finally:
        shutil.rmtree(secure_dir, ignore_errors=True)


if __name__ == "__main__":
    test_fast_detector_correctness_and_speedup()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
