#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

HOME = "/home/user"
PIPELINE = os.path.join(HOME, "pipeline.sh")
CI_FILE = os.path.join(HOME, "bootstrap_ci.txt")


class LCG:
    def __init__(self, seed):
        self.state = seed

    def next_rand(self):
        self.state = (self.state * 1103515245 + 12345) % 2147483648
        return self.state / 2147483648.0


def run_integral_reference(Nc, Nf, seed):
    rng = LCG(seed)

    x_points = []
    for i in range(Nc):
        x_points.append(i * (0.4 / Nc))
    for i in range(Nf):
        x_points.append(0.4 + i * (0.2 / Nf))
    for i in range(Nc + 1):
        x_points.append(0.6 + i * (0.4 / Nc))

    y_points = []
    for x in x_points:
        noise = (rng.next_rand() * 0.1) - 0.05
        y_points.append(math.exp(-100 * (x - 0.5) ** 2) + noise)

    result = 0.0
    for i in range(len(x_points) - 1):
        result += (y_points[i] + y_points[i + 1]) * 0.5 * (x_points[i + 1] - x_points[i])
    return result


def bootstrap_reference(values):
    rng = LCG(42)
    means = []
    for _ in range(1000):
        total = 0.0
        for _ in range(50):
            total += values[int(rng.next_rand() * 50)]
        means.append(total / 50.0)
    means.sort()
    return f"[{means[24]:.6f}, {means[974]:.6f}]"


def get_expected_ci():
    values = [run_integral_reference(10, 50, seed) for seed in range(1, 51)]
    return bootstrap_reference(values)


def execute_pipeline():
    result = subprocess.run(
        [PIPELINE], cwd=HOME, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def read_ci():
    assert os.path.exists(CI_FILE), f"{CI_FILE} was not created by pipeline.sh."
    with open(CI_FILE, "r") as f:
        return f.read().strip()


def test_pipeline_execution():
    """Keep the original end-to-end assertion for the required configuration."""
    assert os.path.exists(PIPELINE), f"{PIPELINE} does not exist."
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} is not executable."

    if os.path.exists(CI_FILE):
        os.remove(CI_FILE)

    execute_pipeline()
    content = read_ci()
    expected_content = get_expected_ci()
    assert content == expected_content, (
        f"Expected content '{expected_content}', but got '{content}' in {CI_FILE}."
    )


def test_c_artifacts_and_pipeline_are_real():
    integral_src = os.path.join(HOME, "integral.c")
    bootstrap_src = os.path.join(HOME, "bootstrap.c")

    for path in (integral_src, bootstrap_src):
        assert os.path.isfile(path), f"{path} does not exist or is not a regular file."
        assert not os.path.islink(path), f"{path} must be an actual source file, not a symlink."

    integral_test_bin = "/tmp/verifier_integral"
    bootstrap_test_bin = "/tmp/verifier_bootstrap"
    for path in (integral_test_bin, bootstrap_test_bin):
        if os.path.exists(path):
            os.remove(path)

    compile_integral = subprocess.run(
        ["gcc", "-std=c11", "-O2", integral_src, "-lm", "-o", integral_test_bin],
        capture_output=True, text=True, timeout=30
    )
    assert compile_integral.returncode == 0, (
        f"integral.c did not compile.\nStdout: {compile_integral.stdout}\n"
        f"Stderr: {compile_integral.stderr}"
    )

    compile_bootstrap = subprocess.run(
        ["gcc", "-std=c11", "-O2", bootstrap_src, "-lm", "-o", bootstrap_test_bin],
        capture_output=True, text=True, timeout=30
    )
    assert compile_bootstrap.returncode == 0, (
        f"bootstrap.c did not compile.\nStdout: {compile_bootstrap.stdout}\n"
        f"Stderr: {compile_bootstrap.stderr}"
    )

    # Exercise integral.c on several verifier-derived configurations and seeds.
    number_only = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$")
    cases = [(1, 1, 1), (3, 7, 42), (8, 19, 98765), (13, 4, 2147483647)]
    for Nc, Nf, seed in cases:
        result = subprocess.run(
            [integral_test_bin, str(Nc), str(Nf), str(seed)],
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"integral failed for Nc={Nc}, Nf={Nf}, seed={seed}: {result.stderr}"
        )
        assert result.stderr == "", f"integral wrote unexpected stderr: {result.stderr!r}"
        assert number_only.fullmatch(result.stdout), (
            f"integral must print only one floating-point value, got {result.stdout!r}"
        )
        actual = float(result.stdout.strip())
        expected = run_integral_reference(Nc, Nf, seed)
        assert abs(actual - expected) <= 1.1e-6, (
            f"Wrong integral for Nc={Nc}, Nf={Nf}, seed={seed}: "
            f"expected {expected}, got {actual}"
        )

    # Preserve the submitted sources and modes while testing pipeline coupling.
    original_integral = open(integral_src, "rb").read()
    original_bootstrap = open(bootstrap_src, "rb").read()
    integral_mode = stat.S_IMODE(os.stat(integral_src).st_mode)
    bootstrap_mode = stat.S_IMODE(os.stat(bootstrap_src).st_mode)

    fake_integral = r'''#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    long seed = strtol(argv[3], NULL, 10);
    double value = (double)(seed * seed + 17 * seed) / 1000.0;
    printf("%.6f\n", value);
    return 0;
}
'''
    marker = "[9.876543, 9.876543]"
    marker_bootstrap = f'''#include <stdio.h>
int main(void) {{
    FILE *f = fopen("/home/user/bootstrap_ci.txt", "w");
    if (!f) return 2;
    fprintf(f, "{marker}\\n");
    return fclose(f) != 0;
}}
'''

    try:
        # Substitute only integral.c. A compliant pipeline must compile and run it,
        # feed its 50 values to the submitted bootstrap.c, and produce the derived CI.
        with open(integral_src, "w") as f:
            f.write(fake_integral)
        for path in (os.path.join(HOME, "integral"), os.path.join(HOME, "bootstrap"), CI_FILE):
            if os.path.lexists(path):
                os.remove(path)

        execute_pipeline()
        synthetic_values = [
            float(f"{(seed * seed + 17 * seed) / 1000.0:.6f}")
            for seed in range(1, 51)
        ]
        expected_synthetic = bootstrap_reference(synthetic_values)
        assert read_ci() == expected_synthetic, (
            "pipeline did not compile/run integral.c and bootstrap the resulting 50 values"
        )

        # Substitute bootstrap.c with a marker implementation. Seeing the marker
        # proves pipeline.sh compiles and invokes the requested bootstrap artifact.
        with open(bootstrap_src, "w") as f:
            f.write(marker_bootstrap)
        for path in (os.path.join(HOME, "bootstrap"), CI_FILE):
            if os.path.lexists(path):
                os.remove(path)

        execute_pipeline()
        assert read_ci() == marker, (
            "pipeline.sh did not compile and invoke bootstrap.c"
        )
    finally:
        with open(integral_src, "wb") as f:
            f.write(original_integral)
        with open(bootstrap_src, "wb") as f:
            f.write(original_bootstrap)
        os.chmod(integral_src, integral_mode)
        os.chmod(bootstrap_src, bootstrap_mode)

    # Re-run the restored submission so the final state also satisfies the original check.
    for path in (os.path.join(HOME, "integral"), os.path.join(HOME, "bootstrap"), CI_FILE):
        if os.path.lexists(path):
            os.remove(path)
    execute_pipeline()
    assert read_ci() == get_expected_ci()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
