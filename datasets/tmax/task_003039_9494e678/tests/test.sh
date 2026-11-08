#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import struct
import subprocess
import tempfile

SOURCE = "/home/user/integrator.c"
EXECUTABLE = "/home/user/integrator"
OUTPUT = "/home/user/output.bin"
DISTANCE = "/home/user/final_distance.txt"


def expected_points():
    x, y = 1.0, 0.0
    h = 0.1
    tol = 1e-6
    points = []
    for _ in range(1000):
        error = h * h * 0.5
        if error <= 0:
            error = 1e-15
        h = h * 0.9 * ((tol / error) ** 0.2)
        x += y * h
        y -= x * h
        points.append((x, y))
    return points


def read_output():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} does not exist. Did you run the executable?"
    assert os.path.getsize(OUTPUT) > 0, f"File {OUTPUT} is empty."
    assert os.path.getsize(OUTPUT) == 1000 * 2 * 8, \
        f"Expected 1000 double pairs in {OUTPUT}."
    with open(OUTPUT, "rb") as f:
        data = f.read()
    values = struct.unpack("=2000d", data)
    return data, list(zip(values[0::2], values[1::2]))


def assert_expected_output(points):
    expected = expected_points()
    assert len(points) == len(expected)
    for i, ((x, y), (ex, ey)) in enumerate(zip(points, expected)):
        assert math.isfinite(x) and math.isfinite(y), f"Non-finite output at pair {i}."
        assert math.isclose(x, ex, rel_tol=1e-12, abs_tol=1e-14), \
            f"Incorrect x value at pair {i}: expected {ex}, got {x}."
        assert math.isclose(y, ey, rel_tol=1e-12, abs_tol=1e-14), \
            f"Incorrect y value at pair {i}: expected {ey}, got {y}."


def test_complete_submission():
    # Preserve the original source assertions.
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "tol / error" in content, \
        "The logic bug was not fixed. Expected 'tol / error' in step_update."
    assert "error / tol" not in content, \
        "The buggy logic 'error / tol' is still present in the file."

    # Exercise step_update directly so comments or unrelated strings cannot satisfy the check.
    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, "integrator.o")
        harness_c = os.path.join(td, "harness.c")
        harness = os.path.join(td, "harness")
        rebuilt = os.path.join(td, "integrator")
        with open(harness_c, "w") as f:
            f.write(r'''#include <math.h>
#include <stdio.h>
void step_update(double *h, double error, double tol);
int main(void) {
    const double hs[] = {0.1, 0.003, 2.0, 0.7};
    const double errors[] = {0.005, 1e-12, 4.0, 0.0};
    const double tols[] = {1e-6, 1e-6, 0.25, 1e-5};
    for (int i = 0; i < 4; ++i) {
        double h = hs[i];
        double error = errors[i] <= 0.0 ? 1e-15 : errors[i];
        double expected = hs[i] * 0.9 * pow(tols[i] / error, 0.2);
        step_update(&h, errors[i], tols[i]);
        if (!isfinite(h) || fabs(h - expected) > 1e-12 * fmax(1.0, fabs(expected))) {
            fprintf(stderr, "step_update case %d: expected %.17g, got %.17g\n", i, expected, h);
            return 1;
        }
    }
    return 0;
}
''')
        subprocess.run(
            ["gcc", "-O2", "-Dmain=integrator_program_main", "-c", SOURCE, "-o", obj],
            check=True, timeout=30
        )
        subprocess.run(["gcc", "-O2", harness_c, obj, "-lm", "-o", harness],
                       check=True, timeout=30)
        subprocess.run([harness], check=True, timeout=10)

        # Compile the complete submitted source to ensure it is valid and executable.
        subprocess.run(["gcc", "-O2", SOURCE, "-lm", "-o", rebuilt],
                       check=True, timeout=30)

        # Preserve the original executable assertions and require an actual native binary.
        assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
        assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
        with open(EXECUTABLE, "rb") as f:
            assert f.read(4) == b"\x7fELF", \
                f"File {EXECUTABLE} is not a compiled ELF executable."

        # Remove any pre-created output, run the demanded artifact, and validate every pair.
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        subprocess.run([EXECUTABLE], check=True, timeout=20, cwd="/home/user")
        submitted_data, submitted_points = read_output()
        assert_expected_output(submitted_points)

        # Run a fresh build of the submitted source and require identical generated data.
        os.remove(OUTPUT)
        subprocess.run([rebuilt], check=True, timeout=20, cwd="/home/user")
        rebuilt_data, rebuilt_points = read_output()
        assert rebuilt_data == submitted_data, \
            "The installed executable's output does not match a fresh build of integrator.c."
        assert_expected_output(rebuilt_points)

        # Leave output.bin containing the data produced by the submitted executable.
        with open(OUTPUT, "wb") as f:
            f.write(submitted_data)

    # Preserve the independently recomputed final-distance assertion.
    assert os.path.isfile(DISTANCE), f"File {DISTANCE} does not exist."
    final_x, final_y = expected_points()[-1]
    expected_distance = math.sqrt(final_x * final_x + final_y * final_y)
    expected_str = f"{expected_distance:.4f}"
    with open(DISTANCE, "r") as f:
        actual_str = f.read().strip()
    assert actual_str == expected_str, \
        f"Expected distance {expected_str}, but got {actual_str} in {DISTANCE}."

    # Also tie the reported distance directly to the freshly generated binary's final pair.
    actual_x, actual_y = submitted_points[-1]
    assert actual_str == f"{math.hypot(actual_x, actual_y):.4f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
