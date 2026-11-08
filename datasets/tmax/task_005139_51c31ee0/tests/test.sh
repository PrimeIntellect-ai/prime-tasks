#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import subprocess
import tempfile
from pathlib import Path

import pytest

REPO = "/home/user/solver_repo"
FILTER = os.path.join(REPO, "filter.py")


def run_historical_wrapper(commit):
    """Evaluate the historical wrapper with an immutable edge-case harness."""
    source = subprocess.check_output(
        ["git", "show", f"{commit}:wrapper.py"], cwd=REPO
    )
    with tempfile.TemporaryDirectory() as td:
        wrapper_path = Path(td) / "wrapper.py"
        runner_path = Path(td) / "runner.py"
        wrapper_path.write_bytes(source)
        runner_path.write_text(
            "import importlib.util\n"
            "spec = importlib.util.spec_from_file_location('historical_wrapper', "
            + repr(str(wrapper_path)) + ")\n"
            "module = importlib.util.module_from_spec(spec)\n"
            "spec.loader.exec_module(module)\n"
            "value = module.solve(1, -6, 11, -6, 0, max_iter=10)\n"
            "print('TRUE' if value is True else 'FALSE' if value is False else 'OTHER')\n"
        )
        result = subprocess.run(
            ["python3", "-I", str(runner_path)],
            cwd=td,
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Could not evaluate wrapper.py at {commit}: {result.stderr}"
        )
        return result.stdout.strip()


def test_bad_commit_hash():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_file), f"{bad_commit_file} does not exist."
    student_hash = Path(bad_commit_file).read_text().strip()

    assert len(student_hash) == 40, "The commit hash in bad_commit.txt must be 40 characters."
    assert re.fullmatch(r"[0-9a-fA-F]{40}", student_hash), "The commit hash must be hexadecimal."

    try:
        object_type = subprocess.check_output(
            ["git", "cat-file", "-t", student_hash], cwd=REPO, text=True
        ).strip()
        assert object_type == "commit", "The submitted hash does not identify a commit."

        parents = subprocess.check_output(
            ["git", "show", "-s", "--format=%P", student_hash], cwd=REPO, text=True
        ).strip().split()
        assert len(parents) == 1, "The reported regression commit must have one parent."
        parent_hash = subprocess.check_output(
            ["git", "rev-parse", f"{student_hash}^"], cwd=REPO, text=True
        ).strip()

        bad_result = run_historical_wrapper(student_hash)
        parent_result = run_historical_wrapper(parent_hash)
        assert bad_result == "FALSE", "The submitted commit does not exhibit the edge-case regression."
        assert parent_result == "TRUE", "The parent of the submitted commit already exhibits the regression."
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"Failed to validate bad commit hash: {exc}")


def test_wrapper_fixed():
    test_edge_path = os.path.join(REPO, "test_edge.py")
    wrapper_path = os.path.join(REPO, "wrapper.py")
    assert os.path.isfile(test_edge_path), f"{test_edge_path} does not exist."
    assert os.path.isfile(wrapper_path), f"{wrapper_path} does not exist."

    try:
        subprocess.check_call(["python3", "test_edge.py"], cwd=REPO, timeout=10)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        pytest.fail("test_edge.py failed. The logic in wrapper.py is not fixed.")

    # Do not trust the editable test_edge.py alone: directly exercise the required bound.
    with tempfile.TemporaryDirectory() as td:
        runner = Path(td) / "check_wrapper.py"
        runner.write_text(
            "import importlib.util\n"
            f"spec = importlib.util.spec_from_file_location('submitted_wrapper', {wrapper_path!r})\n"
            "module = importlib.util.module_from_spec(spec)\n"
            "spec.loader.exec_module(module)\n"
            "checks = []\n"
            "for limit in (10, 11, 25, 100):\n"
            "    checks.append(module.solve(1, -6, 11, -6, 0, max_iter=limit) is True)\n"
            "for limit in (0, 3, 9):\n"
            "    checks.append(module.solve(1, -6, 11, -6, 0, max_iter=limit) is False)\n"
            "raise SystemExit(0 if all(checks) else 1)\n"
        )
        result = subprocess.run(
            ["python3", "-I", str(runner)], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            "wrapper.py does not correctly honor convergence bounds: " + result.stderr
        )


def test_filter_script_exists():
    assert os.path.isfile(FILTER), f"filter.py not found at {FILTER}"


def run_filter(path):
    return subprocess.run(
        ["python3", FILTER, str(path)], capture_output=True, text=True, timeout=5
    )


def safe_newton(values):
    a, b, c, d, x = values
    for _ in range(100):
        f = a*x*x*x + b*x*x + c*x + d
        df = 3*a*x*x + 2*b*x + c
        if not math.isfinite(f) or not math.isfinite(df) or abs(df) < 1e-9:
            return False
        x = x - f/df
        if not math.isfinite(x):
            return False
    f = a*x*x*x + b*x*x + c*x + d
    return math.isfinite(f) and abs(f) < 1e-7


def test_adversarial_corpus():
    clean_dirs = ["/home/user/corpora/clean"]
    evil_dirs = ["/home/user/corpora/evil"]

    # Exercise the hidden corpus that setup actually creates.
    if os.path.isdir("/home/user/.hidden_corpora/clean"):
        clean_dirs.append("/home/user/.hidden_corpora/clean")
    if os.path.isdir("/home/user/.hidden_corpora/evil"):
        evil_dirs.append("/home/user/.hidden_corpora/evil")

    clean_files = [p for d in clean_dirs for p in glob.glob(os.path.join(d, "*.csv"))]
    evil_files = [p for d in evil_dirs for p in glob.glob(os.path.join(d, "*.csv"))]
    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    failed_clean = []
    for path in clean_files:
        result = run_filter(path)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(path))

    failed_evil = []
    for path in evil_files:
        result = run_filter(path)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(path))

    assert not failed_clean, f"Clean inputs rejected: {', '.join(failed_clean)}"
    assert not failed_evil, f"Evil inputs did not exit 1: {', '.join(failed_evil)}"


def test_generated_extended_corpus():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as td:
        base = Path(td)
        clean = base / "clean"
        evil = base / "evil"
        clean.mkdir()
        evil.mkdir()

        # Generate nontrivial convergent cubics from secret roots and nearby guesses.
        made = 0
        attempts = 0
        while made < 24 and attempts < 1000:
            attempts += 1
            roots = rng.sample(range(-12, 13), 3)
            if min(abs(roots[i] - roots[j]) for i in range(3) for j in range(i)) < 2:
                continue
            r1, r2, r3 = roots
            a = float(rng.choice([1, 2, 3]))
            b = -a * (r1 + r2 + r3)
            c = a * (r1*r2 + r1*r3 + r2*r3)
            d = -a * r1*r2*r3
            x0 = float(rng.choice(roots)) + rng.choice([-0.5, -0.25, 0.25, 0.5])
            values = (a, b, c, d, x0)
            if not safe_newton(values):
                continue
            path = clean / f"clean_{made}_{rng.randrange(1 << 30)}.csv"
            path.write_text(",".join(format(v, ".17g") for v in values) + "\n")
            made += 1
        assert made == 24, "Verifier could not construct its clean corpus."

        # Construct inputs whose derivative is exactly zero at the initial guess.
        for i in range(24):
            a = rng.choice([-4, -3, -2, -1, 1, 2, 3, 4])
            b = rng.randint(-8, 8)
            x0 = rng.randint(-6, 6)
            c = -3*a*x0*x0 - 2*b*x0
            f_without_d = a*x0**3 + b*x0**2 + c*x0
            d = -f_without_d + rng.choice([-7, -3, -1, 1, 3, 7])
            (evil / f"zero_derivative_{i}_{rng.randrange(1 << 30)}.csv").write_text(
                f"{a},{b},{c},{d},{x0}\n"
            )

        malformed = [
            "", "1,2,3,4\n", "1,2,3,4,5,6\n", "1,0,0,-1,foo\n",
            "1,0,0,-1,nan\n", "1,0,0,-1,inf\n", "1e309,0,0,-1,2\n",
            "1,0,0,-1,2\n1,0,0,-1,2\n", ",,,,\n", "not,csv,data\n",
        ]
        for i, contents in enumerate(malformed):
            (evil / f"malformed_{i}_{rng.randrange(1 << 30)}.csv").write_text(contents)

        # This Newton sequence oscillates 0 -> 1 -> 0 and never converges.
        (evil / f"oscillation_{rng.randrange(1 << 30)}.csv").write_text("1,0,-2,2,0\n")
        (evil / f"degenerate_{rng.randrange(1 << 30)}.csv").write_text("0,0,0,1,0\n")

        failures = []
        for path in clean.glob("*.csv"):
            result = run_filter(path)
            if result.returncode != 0:
                failures.append(f"clean {path.name} returned {result.returncode}")
        for path in evil.glob("*.csv"):
            result = run_filter(path)
            if result.returncode != 1:
                failures.append(f"evil {path.name} returned {result.returncode}")

        assert not failures, "Generated corpus failures: " + "; ".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
