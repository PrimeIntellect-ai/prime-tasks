#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import collections
import math
import os
import random
import re
import shutil
import stat
import string
import subprocess
import tempfile
import time

import pytest

ENCODER = "/home/user/src/encoder"
ORACLE = "/app/oracle_bin"
BENCHMARK = "/home/user/benchmark.sh"
REPORT = "/home/user/report.log"


def test_makefile_builds_encoder():
    makefile = "/home/user/src/Makefile"
    assert os.path.isfile(makefile), f"Makefile not found at {makefile}"
    result = subprocess.run(
        ["make", "-B"], cwd="/home/user/src", capture_output=True,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Makefile failed to build encoder.\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_encoder_compiled_and_executable():
    path = ENCODER
    assert os.path.isfile(path), f"Compiled encoder binary not found at {path}"
    assert not os.path.islink(path), "Compiled encoder must not be a symlink"
    assert os.access(path, os.X_OK), f"Compiled encoder binary at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled encoder is not an ELF executable"
    assert not os.path.samefile(path, ORACLE), "Encoder must not be the oracle binary"
    with open(path, "rb") as f1, open(ORACLE, "rb") as f2:
        assert f1.read() != f2.read(), "Encoder is byte-identical to the oracle binary"


def test_source_is_warning_free_and_memory_safe_on_edge_cases():
    source = "/home/user/src/encoder.c"
    assert os.path.isfile(source), f"Source file not found at {source}"
    asan_binary = "/tmp/encoder_asan"
    build = subprocess.run([
        "gcc", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
        "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
        source, "-o", asan_binary
    ], capture_output=True, text=True, timeout=30)
    assert build.returncode == 0, (
        f"encoder.c does not compile cleanly with safety instrumentation.\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    cases = [b"", b"A", b"A" * 600, b"Aa0Zz9", (b"ABC123" * 200)]
    for data in cases:
        tested = subprocess.run(
            [asan_binary], input=data, capture_output=True, env=env, timeout=10
        )
        expected = subprocess.run(
            [ORACLE], input=data, capture_output=True, check=True, timeout=10
        )
        assert tested.returncode == 0, (
            f"Instrumented encoder failed on edge-case input of length {len(data)}.\n"
            f"stderr:\n{tested.stderr.decode(errors='replace')}"
        )
        assert tested.stdout == expected.stdout, (
            f"Instrumented encoder output mismatch for input length {len(data)}"
        )


def test_benchmark_script_exists_and_executable():
    path = BENCHMARK
    assert os.path.isfile(path), f"Benchmark script not found at {path}"
    assert os.access(path, os.X_OK), f"Benchmark script at {path} is not executable"


def _install_recording_wrapper(path, original, logdir, label, delay):
    wrapper = f'''#!/bin/bash
start=$(date +%s%N)
tmp=$(mktemp "{logdir}/{label}.input.XXXXXX") || exit 125
cat > "$tmp" || exit 125
sleep {delay}
"{original}" < "$tmp"
rc=$?
end=$(date +%s%N)
printf '%s\\t%s\\t%s\\n' "$tmp" "$start" "$end" >> "{logdir}/{label}.log"
exit "$rc"
'''
    with open(path, "w") as f:
        f.write(wrapper)
    os.chmod(path, 0o755)


def test_benchmark_executes_exactly_500_equivalence_and_timing_runs():
    logdir = tempfile.mkdtemp(prefix="benchmark-audit-", dir="/tmp")
    os.chmod(logdir, 0o777)
    original_encoder = os.path.join(logdir, "real_encoder")
    original_oracle = os.path.join(logdir, "real_oracle")
    old_src_mode = stat.S_IMODE(os.stat("/home/user/src").st_mode)
    old_app_mode = stat.S_IMODE(os.stat("/app").st_mode)

    os.rename(ENCODER, original_encoder)
    os.rename(ORACLE, original_oracle)
    os.chmod(original_encoder, 0o755)
    os.chmod(original_oracle, 0o755)
    _install_recording_wrapper(ENCODER, original_encoder, logdir, "encoder", "0.015")
    _install_recording_wrapper(ORACLE, original_oracle, logdir, "oracle", "0.001")
    os.chmod("/home/user/src", 0o755)
    os.chmod("/app", 0o755)

    def cleanup():
        try:
            if os.path.lexists(ENCODER):
                os.unlink(ENCODER)
            if os.path.exists(original_encoder):
                os.rename(original_encoder, ENCODER)
            if os.path.lexists(ORACLE):
                os.unlink(ORACLE)
            if os.path.exists(original_oracle):
                os.rename(original_oracle, ORACLE)
            os.chmod("/home/user/src", old_src_mode)
            os.chmod("/app", old_app_mode)
        except Exception:
            pass
    atexit.register(cleanup)

    if os.path.exists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", BENCHMARK],
        capture_output=True, timeout=180
    )
    assert result.returncode == 0, (
        f"benchmark.sh exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout.decode(errors='replace')}\n"
        f"stderr:\n{result.stderr.decode(errors='replace')}"
    )

    def records(label):
        path = os.path.join(logdir, label + ".log")
        assert os.path.isfile(path), f"benchmark.sh never invoked {label}"
        parsed = []
        with open(path) as f:
            for line in f:
                fields = line.rstrip("\n").split("\t")
                assert len(fields) == 3, f"Malformed invocation record for {label}"
                input_path, start, end = fields
                with open(input_path, "rb") as inp:
                    data = inp.read()
                parsed.append((data, int(start), int(end)))
        return parsed

    enc_records = records("encoder")
    oracle_records = records("oracle")
    assert len(enc_records) == 500, (
        f"benchmark.sh must invoke the C encoder exactly 500 times, got {len(enc_records)}"
    )
    assert len(oracle_records) == 500, (
        f"benchmark.sh must invoke the oracle exactly 500 times, got {len(oracle_records)}"
    )

    enc_inputs = [r[0] for r in enc_records]
    oracle_inputs = [r[0] for r in oracle_records]
    assert collections.Counter(enc_inputs) == collections.Counter(oracle_inputs), (
        "The encoder and oracle were not fed exactly the same 500 generated inputs"
    )
    allowed = set((string.ascii_letters + string.digits).encode())
    assert all(10 <= len(data) <= 1000 for data in enc_inputs), (
        "Every generated input must have length between 10 and 1000"
    )
    assert all(set(data) <= allowed for data in enc_inputs), (
        "Generated inputs must contain only alphanumeric characters"
    )
    assert len({len(data) for data in enc_inputs}) > 1, (
        "Generated inputs must have varying lengths"
    )

    assert os.path.isfile(REPORT), f"Report log not found at {REPORT}"
    with open(REPORT, "rb") as f:
        raw = f.read()
    assert re.fullmatch(rb"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\n?", raw), (
        "report.log must contain exactly one line containing only a floating-point number"
    )
    reported = float(raw.strip())
    assert math.isfinite(reported) and reported > 0, "Reported speedup must be finite and positive"

    enc_ns = sum(end - start for _, start, end in enc_records)
    oracle_ns = sum(end - start for _, start, end in oracle_records)
    observed = enc_ns / oracle_ns
    relative_error = abs(reported - observed) / observed
    assert relative_error <= 0.35, (
        f"benchmark.sh did not report the measured 500-run timing ratio: "
        f"reported {reported:.4f}, observed {observed:.4f}, "
        f"relative error {relative_error:.4f}"
    )


def test_report_log_exists():
    path = REPORT
    assert os.path.isfile(path), f"Report log not found at {path}"


def test_encoder_correctness():
    """Verify that the compiled encoder produces the exact same output as the oracle."""
    for _ in range(10):
        length = random.randint(10, 1000)
        test_str = ''.join(random.choices(string.ascii_letters + string.digits, k=length)).encode()
        try:
            res_encoder = subprocess.run([ENCODER], input=test_str, capture_output=True, check=True, timeout=2)
            res_oracle = subprocess.run([ORACLE], input=test_str, capture_output=True, check=True, timeout=2)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Execution failed for string of length {length}. Return code: {e.returncode}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Execution timed out for string of length {length}")
        assert res_encoder.stdout == res_oracle.stdout, f"Output mismatch for input length {length}"


def test_speedup_metric():
    """Verify the accuracy of the calculated execution speedup ratio."""
    try:
        with open(REPORT, 'r') as f:
            content = f.read().strip()
            agent_speedup = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {REPORT} as a float: '{content}'")

    c_time = 0
    oracle_time = 0
    for _ in range(100):
        test_str = ''.join(random.choices(string.ascii_letters + string.digits, k=500)).encode()
        t0 = time.time()
        subprocess.run([ENCODER], input=test_str, stdout=subprocess.DEVNULL)
        c_time += time.time() - t0
        t0 = time.time()
        subprocess.run([ORACLE], input=test_str, stdout=subprocess.DEVNULL)
        oracle_time += time.time() - t0

    true_speedup = c_time / oracle_time
    relative_error = abs(agent_speedup - true_speedup) / true_speedup
    assert relative_error <= 0.25, (
        f"Speedup ratio relative error is too high. "
        f"Agent reported: {agent_speedup:.4f}, True speedup: {true_speedup:.4f}, "
        f"Relative error: {relative_error:.4f} (Threshold: <= 0.25)"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
