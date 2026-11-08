#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import runpy
import secrets
import shutil
import subprocess
import tempfile

import pytest

ORACLE = "/app/vol_estimator"
AGENT = "/home/user/fast_vol"
SOURCE = "/home/user/fast_vol.c"


def run(cmd, timeout=30):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def oracle_output(args):
    result = run([ORACLE] + list(args))
    assert result.returncode == 0, f"Oracle failed on args {args}: {result.stderr}"
    return result.stdout


def test_files_exist():
    assert os.path.exists("/home/user/validate.py"), "/home/user/validate.py does not exist"
    assert os.path.exists("/home/user/convergence.png"), "/home/user/convergence.png does not exist"
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist"
    assert os.path.exists(AGENT), f"{AGENT} does not exist"
    assert os.access(AGENT, os.X_OK), f"{AGENT} is not executable"
    assert os.path.isfile(AGENT), f"{AGENT} is not a regular file"
    assert not os.path.islink(AGENT), f"{AGENT} must not be a symlink"

    with open(AGENT, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT} is not an ELF executable"
    assert not os.path.samefile(AGENT, ORACLE), "fast_vol must not be the legacy executable"
    with open(AGENT, "rb") as a, open(ORACLE, "rb") as o:
        assert a.read() != o.read(), "fast_vol must not be a byte-for-byte copy of the legacy executable"


def test_fuzz_equivalence():
    oracle = ORACLE
    agent = AGENT

    assert os.path.exists(oracle), f"Oracle {oracle} missing"
    assert os.path.exists(agent), f"Agent binary {agent} missing"

    random.seed(42)

    for _ in range(50):
        seed = random.randint(1, 65535)
        n = random.randint(10, 100000)
        r = round(random.uniform(0.1, 20.0), 2)

        args = [str(seed), str(n), f"{r:.2f}"]

        oracle_cmd = [oracle] + args
        agent_cmd = [agent] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on args {args}"
        assert agent_res.returncode == 0, f"Agent failed on args {args}"

        assert oracle_res.stdout == agent_res.stdout, (
            f"Output mismatch on args {args}.\n"
            f"Oracle output: {oracle_res.stdout.strip()}\n"
            f"Agent output: {agent_res.stdout.strip()}"
        )


def copy_runtime_dependencies(binary, root):
    result = run(["ldd", binary])
    combined = result.stdout + result.stderr
    if result.returncode != 0 and "not a dynamic executable" not in combined:
        pytest.fail(f"Could not inspect fast_vol runtime dependencies: {combined}")

    paths = set(re.findall(r"(?:=>\s*)?(/[^\s()]+)", combined))
    for path in paths:
        if not os.path.isfile(path):
            continue
        destination = os.path.join(root, path.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(path, destination)


def test_installed_executable_is_self_contained():
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(12):
        args = [
            str(rng.randrange(0, 2**31)),
            str(rng.randrange(25, 25000)),
            f"{rng.uniform(0.05, 50.0):.8f}",
        ]
        cases.append((args, oracle_output(args)))

    with tempfile.TemporaryDirectory() as root:
        shutil.copy2(AGENT, os.path.join(root, "fast_vol"))
        os.chmod(os.path.join(root, "fast_vol"), 0o755)
        copy_runtime_dependencies(AGENT, root)

        for args, expected in cases:
            result = run(["chroot", root, "/fast_vol"] + args)
            assert result.returncode == 0, (
                f"Installed fast_vol is not independently runnable on args {args}: {result.stderr}"
            )
            assert result.stdout == expected, f"Installed fast_vol mismatch on args {args}"


def test_source_builds_and_implements_algorithm():
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(16):
        args = [
            str(rng.randrange(0, 2**31)),
            str(rng.randrange(10, 30000)),
            f"{rng.uniform(0.01, 100.0):.10f}",
        ]
        cases.append((args, oracle_output(args)))

    with tempfile.TemporaryDirectory() as root:
        rebuilt = os.path.join(root, "fast_vol")
        build = run(["gcc", "-O3", "-static", SOURCE, "-o", rebuilt], timeout=60)
        assert build.returncode == 0, f"fast_vol.c did not compile: {build.stderr}"
        assert os.access(rebuilt, os.X_OK), "Rebuilt fast_vol is not executable"

        for args, expected in cases:
            result = run(["chroot", root, "/fast_vol"] + args)
            assert result.returncode == 0, (
                f"Program rebuilt from fast_vol.c failed in isolation on args {args}: {result.stderr}"
            )
            assert result.stdout == expected, f"Rebuilt fast_vol mismatch on args {args}"


def test_validation_script_executes_and_plots_correct_errors(monkeypatch):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.axes

    ns = list(range(1000, 10001, 1000))
    expected_counts = []
    for n in ns:
        out = oracle_output(["42", str(n), "5.0"])
        expected_counts.append(int(out.strip()))
    analytical = (16.0 / 3.0) * 5.0**3
    expected_errors = [abs((count / n) * (2.0 * 5.0)**3 - analytical)
                       for count, n in zip(expected_counts, ns)]

    captured = []
    original_plot = matplotlib.axes.Axes.plot
    original_scatter = matplotlib.axes.Axes.scatter
    original_bar = matplotlib.axes.Axes.bar

    def values(obj):
        try:
            return [float(v) for v in obj]
        except TypeError:
            return [float(obj)]

    def recording_plot(self, *args, **kwargs):
        if len(args) >= 2:
            captured.append((values(args[0]), values(args[1])))
        elif len(args) == 1:
            captured.append((None, values(args[0])))
        return original_plot(self, *args, **kwargs)

    def recording_scatter(self, x, y, *args, **kwargs):
        captured.append((values(x), values(y)))
        return original_scatter(self, x, y, *args, **kwargs)

    def recording_bar(self, x, height, *args, **kwargs):
        captured.append((values(x), values(height)))
        return original_bar(self, x, height, *args, **kwargs)

    monkeypatch.setattr(matplotlib.axes.Axes, "plot", recording_plot)
    monkeypatch.setattr(matplotlib.axes.Axes, "scatter", recording_scatter)
    monkeypatch.setattr(matplotlib.axes.Axes, "bar", recording_bar)
    monkeypatch.setenv("MPLBACKEND", "Agg")

    output = "/home/user/convergence.png"
    if os.path.exists(output):
        os.unlink(output)

    old_argv = list(__import__("sys").argv)
    try:
        __import__("sys").argv = ["/home/user/validate.py"]
        runpy.run_path("/home/user/validate.py", run_name="__main__")
    finally:
        __import__("sys").argv = old_argv

    assert os.path.isfile(output), "validate.py did not create convergence.png"
    assert os.path.getsize(output) > 1000, "convergence.png is empty or invalid"
    with open(output, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "convergence.png is not a PNG file"

    def close_series(series):
        x, y = series
        if len(y) != len(expected_errors):
            return False
        if not all(math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-9)
                   for a, b in zip(y, expected_errors)):
            return False
        return x is None or (len(x) == len(ns) and all(
            math.isclose(a, b, rel_tol=0.0, abs_tol=1e-9) for a, b in zip(x, ns)))

    assert any(close_series(series) for series in captured), (
        "validate.py did not plot the absolute Monte Carlo errors for N=1000..10000"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
