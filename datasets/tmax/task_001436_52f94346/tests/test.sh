#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile

PROJECT = "/home/user/project"
COMPUTE_C = os.path.join(PROJECT, "compute.c")


def test_test_script_success():
    """Run test.sh and ensure it returns 0 and outputs BUILD SUCCESS."""
    test_sh_path = os.path.join(PROJECT, "test.sh")
    assert os.path.isfile(test_sh_path), f"{test_sh_path} is missing"

    result = subprocess.run(
        [test_sh_path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )

    assert result.returncode == 0, (
        f"test.sh failed with return code {result.returncode}. "
        f"Output:\n{result.stdout}\n{result.stderr}"
    )
    assert "BUILD SUCCESS" in result.stdout, "test.sh did not output 'BUILD SUCCESS'"


def test_output_matches_expected():
    """Ensure output.txt matches expected.txt after running the pipeline."""
    output_path = os.path.join(PROJECT, "output.txt")
    expected_path = os.path.join(PROJECT, "expected.txt")

    assert os.path.isfile(output_path), f"{output_path} is missing"
    assert os.path.isfile(expected_path), f"{expected_path} is missing"

    with open(output_path, "r") as f:
        output_content = f.read().strip()
    with open(expected_path, "r") as f:
        expected_content = f.read().strip()

    assert output_content == expected_content, (
        f"Contents of {output_path} do not match {expected_path}"
    )


def test_compute_c_fixed():
    """Ensure the original buggy expression is gone from compute.c."""
    assert os.path.isfile(COMPUTE_C), f"{COMPUTE_C} is missing"
    with open(COMPUTE_C, "r") as f:
        content = f.read()

    content_no_spaces = content.replace(" ", "")
    assert "b*b+4*a*c" not in content_no_spaces, (
        "The mathematical bug (b*b + 4*a*c) is still present in compute.c"
    )


def test_compute_on_independently_derived_inputs():
    """Compile compute.c directly and test unseen equations without trusted files."""
    assert os.path.isfile(COMPUTE_C), f"{COMPUTE_C} is missing"

    with tempfile.TemporaryDirectory() as work:
        binary = os.path.join(work, "compute")
        compile_result = subprocess.run(
            ["gcc", COMPUTE_C, "-o", binary, "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"compute.c did not compile:\n{compile_result.stdout}\n"
            f"{compile_result.stderr}"
        )

        rng = random.SystemRandom()
        cases = []

        # Equations generated from independently selected integral roots.
        while len(cases) < 16:
            a = rng.randint(1, 9)
            r1 = rng.randint(-12, 12)
            r2 = rng.randint(-12, 12)
            if r1 == r2 and len(cases) % 4 != 0:
                continue
            cases.append((float(a), float(-a * (r1 + r2)), float(a * r1 * r2)))

        # Positive, non-square discriminants exercise non-integral roots.
        while len(cases) < 26:
            a = rng.randint(1, 8)
            b = rng.randint(-20, 20)
            c = rng.randint(-15, 15)
            d = b * b - 4 * a * c
            if d > 0 and math.isqrt(d) ** 2 != d:
                cases.append((float(a), float(b), float(c)))

        # Equations with no real roots.
        for _ in range(6):
            a = rng.randint(1, 8)
            b = rng.randint(-15, 15)
            c = b * b // (4 * a) + rng.randint(1, 10)
            while b * b - 4 * a * c >= 0:
                c += 1
            cases.append((float(a), float(b), float(c)))

        with open(os.path.join(work, "input.txt"), "w") as f:
            for a, b, c in cases:
                f.write(f"{a:.17g} {b:.17g} {c:.17g}\n")

        run_result = subprocess.run(
            [binary],
            cwd=work,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run_result.returncode == 0, (
            f"compute exited with {run_result.returncode}:\n"
            f"{run_result.stdout}\n{run_result.stderr}"
        )

        output_path = os.path.join(work, "output.txt")
        assert os.path.isfile(output_path), "compute did not create output.txt"
        with open(output_path, "r") as f:
            lines = f.read().splitlines()

        assert len(lines) == len(cases), (
            f"Expected {len(cases)} output rows, got {len(lines)}"
        )

        for index, ((a, b, c), line) in enumerate(zip(cases, lines), 1):
            d = b * b - 4.0 * a * c
            fields = line.split()
            if d < 0:
                assert len(fields) == 1 and fields[0].lower() == "nan", (
                    f"Row {index}: expected NaN for coefficients {(a, b, c)}, got {line!r}"
                )
                continue

            assert len(fields) == 2, f"Row {index}: expected two roots, got {line!r}"
            try:
                actual = (float(fields[0]), float(fields[1]))
            except ValueError:
                raise AssertionError(f"Row {index}: roots are not numeric: {line!r}")

            expected = sorted(
                [(-b + math.sqrt(d)) / (2.0 * a),
                 (-b - math.sqrt(d)) / (2.0 * a)],
                reverse=True,
            )
            assert actual[0] >= actual[1], f"Row {index}: roots are not descending"
            for got, want in zip(actual, expected):
                assert math.isclose(got, want, rel_tol=0.0, abs_tol=0.000051), (
                    f"Row {index}: coefficients {(a, b, c)} produced {actual}, "
                    f"expected approximately {tuple(expected)}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
