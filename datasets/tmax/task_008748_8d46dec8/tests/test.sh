#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import shlex
import shutil
import subprocess
import tempfile
import pytest

HOME = "/home/user"
GRAPH = os.path.join(HOME, "graph.dat")
SOURCE = os.path.join(HOME, "energy_calc.c")
BINARY = os.path.join(HOME, "energy_calc")
OPTIMIZER = os.path.join(HOME, "optimize.py")
OPTIMAL = os.path.join(HOME, "optimal_x.txt")
NUM_STEPS = 1000


def read_edges(path=GRAPH):
    edges = []
    with open(path, "r") as f:
        for line in f:
            if line.strip():
                w, c = map(float, line.split())
                edges.append((w, c))
    return edges


def expected_energy(edges, x):
    dt = 1.0 / NUM_STEPS
    total = 0.0
    for w, c in edges:
        edge_sum = 0.0
        for i in range(NUM_STEPS):
            t = (i + 0.5) * dt
            val = t * x - c
            edge_sum += w * val * val * dt
        total += edge_sum
    return total


def derived_optimum(edges):
    mean_t = 0.5
    mean_t2 = sum(((i + 0.5) / NUM_STEPS) ** 2 for i in range(NUM_STEPS)) / NUM_STEPS
    numerator = mean_t * sum(w * c for w, c in edges)
    denominator = mean_t2 * sum(w for w, _ in edges)
    return min(5.0, max(0.0, numerator / denominator))


def run_calc(path, x, threads=4):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(threads)
    env["OMP_DYNAMIC"] = "FALSE"
    proc = subprocess.run(
        [path, format(x, ".17g")], cwd=HOME, env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=True,
    )
    output = proc.stdout.strip()
    assert re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", output), \
        f"energy_calc produced non-numeric or extra output: {proc.stdout!r}"
    value = float(output)
    assert math.isfinite(value), "energy_calc returned a non-finite value"
    return output, value


def test_optimal_x_file():
    path = "/home/user/optimal_x.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "3.6429", f"Expected optimal_x.txt to contain exactly '3.6429', but got '{content}'."


def test_energy_calc_c_fixed():
    path = "/home/user/energy_calc.c"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "reduction" in content, "The C code does not appear to use an OpenMP reduction clause."
    atomic_pattern = re.compile(r'#pragma\s+omp\s+atomic\s*total_energy\s*\+=', re.MULTILINE)
    assert not atomic_pattern.search(content), "The C code still contains the non-deterministic atomic directive for total_energy."

    # Check active code rather than accepting words placed in comments.
    uncommented = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    uncommented = re.sub(r'//[^\n]*', '', uncommented)
    uncommented = uncommented.replace('\\\n', ' ')
    reduction_pragma = re.compile(
        r'#\s*pragma\s+omp\s+parallel\s+for[^\n]*'
        r'reduction\s*\(\s*\+\s*:\s*total_energy\s*\)',
        re.IGNORECASE,
    )
    assert reduction_pragma.search(uncommented), \
        "The integration loop must use an active OpenMP parallel-for reduction on total_energy."
    assert not re.search(r'#\s*pragma\s+omp\s+atomic\b', uncommented, re.IGNORECASE), \
        "An active OpenMP atomic directive remains in the program."


def test_energy_calc_executable():
    path = "/home/user/energy_calc"
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path) and os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_compiles_and_is_numerically_correct_and_deterministic():
    compiled = tempfile.NamedTemporaryFile(prefix="verified_energy_calc_", delete=False)
    compiled.close()
    os.unlink(compiled.name)
    try:
        subprocess.run(
            ["gcc", "-O2", "-fopenmp", "-lm", "energy_calc.c", "-o", compiled.name],
            cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30, check=True,
        )

        edges = read_edges()
        for x in (0.0, 0.375, 2.25, 3.6429, 5.0):
            expected = expected_energy(edges, x)
            shipped_text, shipped = run_calc(BINARY, x, 4)
            built_text, built = run_calc(compiled.name, x, 4)
            assert math.isclose(shipped, expected, rel_tol=1e-9, abs_tol=2e-7), \
                f"Incorrect energy at x={x}: got {shipped}, expected {expected}"
            assert math.isclose(built, expected, rel_tol=1e-9, abs_tol=2e-7), \
                f"Submitted source computes an incorrect energy at x={x}"
            assert shipped_text == built_text, \
                "The submitted executable does not match the behavior of the submitted source."

        repeated = [run_calc(BINARY, 3.141592653589793, 4)[0] for _ in range(25)]
        assert len(set(repeated)) == 1, \
            f"Repeated runs are not deterministic: observed {sorted(set(repeated))}"

        # Exercise graph input beyond the three setup edges to reject hard-coded answers.
        alternate = [
            (0.20 + (i % 5) * 0.17, -0.75 + i * 0.29)
            for i in range(17)
        ]
        with open(GRAPH, "rb") as f:
            original_graph = f.read()
        try:
            with open(GRAPH, "w") as f:
                for w, c in alternate:
                    f.write(f"{w:.17g} {c:.17g}\n")
            for x in (0.125, 1.75, 4.625):
                expected = expected_energy(alternate, x)
                for executable in (BINARY, compiled.name):
                    _, actual = run_calc(executable, x, 4)
                    assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=2e-7), \
                        f"{executable} did not correctly process graph.dat at x={x}"
        finally:
            with open(GRAPH, "wb") as f:
                f.write(original_graph)
    finally:
        if os.path.exists(compiled.name):
            os.unlink(compiled.name)


def test_optimize_py_exists():
    path = "/home/user/optimize.py"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."


def test_optimize_py_runs_energy_calc_and_writes_the_optimum():
    expected_x = derived_optimum(read_edges())
    expected_text = f"{expected_x:.4f}"
    assert expected_text == "3.6429"

    tempdir = tempfile.mkdtemp(prefix="optimizer_check_")
    real_binary = os.path.join(tempdir, "energy_calc.real")
    call_log = os.path.join(tempdir, "calls.log")
    shutil.copy2(BINARY, real_binary)

    wrapper = (
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$1\" >> {shlex.quote(call_log)}\n"
        f"exec {shlex.quote(real_binary)} \"$@\"\n"
    )

    try:
        with open(BINARY, "w") as f:
            f.write(wrapper)
        os.chmod(BINARY, 0o755)

        proc = subprocess.run(
            ["python3", OPTIMIZER], cwd=HOME, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90,
        )
        assert proc.returncode == 0, \
            f"optimize.py failed with exit code {proc.returncode}: {proc.stderr}"

        assert os.path.exists(call_log), "optimize.py never executed ./energy_calc."
        with open(call_log, "r") as f:
            raw_calls = [line.strip() for line in f if line.strip()]
        calls = [float(value) for value in raw_calls]
        assert len({round(value, 12) for value in calls}) >= 3, \
            "optimize.py did not evaluate enough distinct candidate values to perform an optimization."
        assert all(math.isfinite(value) and -1e-12 <= value <= 5.0 + 1e-12 for value in calls), \
            "optimize.py evaluated energy outside the required bounded range [0.0, 5.0]."
        assert min(abs(value - expected_x) for value in calls) < 0.05, \
            "optimize.py did not search near the graph-derived minimum."

        assert os.path.exists(OPTIMAL), "optimize.py did not create optimal_x.txt."
        with open(OPTIMAL, "r") as f:
            result = f.read().strip()
        assert re.fullmatch(r"\d+\.\d{4}", result), \
            "optimal_x.txt must contain only one value with exactly four decimal places."
        assert result == expected_text, \
            f"optimize.py wrote {result!r}; the graph-derived optimum is {expected_text!r}."
    finally:
        shutil.copy2(real_binary, BINARY)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
