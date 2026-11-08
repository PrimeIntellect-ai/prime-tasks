#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from decimal import Decimal

SOURCE = "/home/user/sensor_service.c"
SOLUTION = "/home/user/solution.txt"
DUMP = "/home/user/crash_dump.bin"


def run(cmd, **kwargs):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=kwargs.pop("timeout", 45), **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(cmd)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def expected_sensor_name():
    assert os.path.isfile(DUMP), f"File {DUMP} is missing."
    with open(DUMP, "rb") as f:
        dump_content = f.read()
    match = re.search(b"(SENSOR_OVERFLOW_[A-Za-z0-9_]+)\\x00", dump_content)
    assert match is not None, "Could not find the malicious sensor name in the crash dump."
    return match.group(1).decode("utf-8")


def test_solution_file_exists_and_correct():
    assert os.path.isfile(SOLUTION), f"File {SOLUTION} is missing."
    expected_name = expected_sensor_name()

    with open(SOLUTION, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {SOLUTION}, but found {len(lines)}."
    assert lines[0] == expected_name, (
        f"Line 1 of {SOLUTION} is incorrect. Expected '{expected_name}', got '{lines[0]}'."
    )
    assert lines[1] == "2.000000", (
        f"Line 2 of {SOLUTION} is incorrect. Expected '2.000000', got '{lines[1]}'."
    )


def test_sensor_service_fixes_applied():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        source_code = f.read()

    # Retain the original source-level assertions.
    assert "free(" in source_code, "Memory leak does not appear to be fixed (no 'free' found)."
    has_mutex = "pthread_mutex_" in source_code
    has_atomic = "_Atomic" in source_code or "__atomic" in source_code or "__sync" in source_code
    assert has_mutex or has_atomic, "Race condition does not appear to be fixed (no mutex or atomic operations found)."
    assert "strcpy(" not in source_code or "strncpy(" in source_code or "snprintf(" in source_code, (
        "Buffer overflow does not appear to be fixed (unsafe 'strcpy' still present without bounds checking)."
    )


def test_compiles_and_produces_correct_total_repeatedly():
    with tempfile.TemporaryDirectory() as td:
        exe = os.path.join(td, "sensor_service")
        run(["gcc", "-std=c11", "-O2", "-pthread", SOURCE, "-lm", "-o", exe])

        # Repeated executions exercise the threaded accumulation rather than trusting solution.txt.
        for _ in range(3):
            result = run([exe], timeout=45)
            assert result.stdout == "2.000000\n", (
                f"Compiled sensor_service produced {result.stdout!r}, expected '2.000000\\n'."
            )


def test_accumulation_on_derived_workload():
    with open(SOURCE, "r") as f:
        source_code = f.read()

    # Build a verifier-derived workload so a hardcoded original answer is insufficient.
    assert "1000000" in source_code, "The required loop count literal was changed or removed."
    assert "0.000001" in source_code, "The required added-value literal was changed or removed."
    iterations = 120000 + secrets.randbelow(80001)
    variant = source_code.replace("1000000", str(iterations))
    expected = format(Decimal(2 * iterations) * Decimal("0.000001"), ".6f") + "\n"

    with tempfile.TemporaryDirectory() as td:
        variant_path = os.path.join(td, "sensor_service_variant.c")
        exe = os.path.join(td, "sensor_service_variant")
        with open(variant_path, "w") as f:
            f.write(variant)
        run(["gcc", "-std=c11", "-O2", "-pthread", variant_path, "-lm", "-o", exe])
        for _ in range(3):
            result = run([exe], timeout=45)
            assert result.stdout == expected, (
                f"Derived workload produced {result.stdout!r}, expected {expected!r}."
            )


def test_process_data_is_bounded_and_leak_free():
    harness = r'''
#include <stddef.h>
void process_data(const char *input_name, double val);
int main(void) {
    for (int i = 0; i < 256; ++i)
        process_data("sensorA", 0.000001);
    for (int i = 0; i < 64; ++i)
        process_data("SENSOR_OVERFLOW_TRIGGER_99281_EXTRA_LONG_PAYLOAD", 0.000001);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, "service.o")
        harness_path = os.path.join(td, "harness.c")
        exe = os.path.join(td, "harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        flags = ["-std=c11", "-O1", "-g", "-fno-omit-frame-pointer",
                 "-fsanitize=address,undefined", "-pthread"]
        run(["gcc", *flags, "-Dmain=sensor_service_original_main", "-c", SOURCE, "-o", obj])
        run(["gcc", *flags, harness_path, obj, "-lm", "-o", exe])

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
        run([exe], env=env, timeout=45)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
