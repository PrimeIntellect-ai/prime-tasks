#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import textwrap
import time
import pytest

HOME = "/home/user"
SIM = os.path.join(HOME, "simulate.py")
FIT = os.path.join(HOME, "fit.sh")
OBS = os.path.join(HOME, "observed.txt")
BEST = os.path.join(HOME, "best_k.txt")
KS = os.path.join(HOME, "ks_dist.txt")
GRID = [round(i / 10, 1) for i in range(1, 16)]


def run(cmd, timeout=60):
    result = subprocess.run(cmd, cwd=HOME, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {cmd!r} failed with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def parse_simulator(k, path=SIM):
    result = run(["python3", path, str(k)], timeout=20)
    lines = result.stdout.strip().splitlines()
    assert len(lines) == 11, f"simulate.py should output exactly 11 points, got {len(lines)}"
    rows = []
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Malformed simulator output line: {line!r}"
        try:
            t, y = map(float, parts)
        except ValueError:
            pytest.fail(f"Non-numeric simulator output line: {line!r}")
        assert math.isfinite(t) and math.isfinite(y), f"Non-finite simulator output: {line!r}"
        rows.append((t, y))
    assert [t for t, _ in rows] == [float(i) for i in range(11)], (
        "simulate.py must output t=0,1,...,10 in order"
    )
    return [y for _, y in rows]


def read_single_float(path):
    assert os.path.isfile(path), f"{path} is missing"
    content = open(path).read().strip()
    assert content and len(content.split()) == 1, f"{path} must contain one number"
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse {content!r} as a float in {path}")
    assert math.isfinite(value), f"{path} contains a non-finite value"
    return value, content


def read_observed():
    rows = []
    with open(OBS) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                rows.append((float(parts[0]), float(parts[1])))
    assert len(rows) == 11, f"observed.txt should have exactly 11 points, got {len(rows)}"
    return rows


def ks_2samp_stdlib(data1, data2):
    n1, n2 = len(data1), len(data2)
    a, b = sorted(data1), sorted(data2)
    values = sorted(set(a + b))
    i = j = 0
    maximum = 0.0
    for x in values:
        while i < n1 and a[i] <= x:
            i += 1
        while j < n2 and b[j] <= x:
            j += 1
        maximum = max(maximum, abs(i / n1 - j / n2))
    return maximum


def expected_best(obs_y, simulations):
    errors = {
        k: sum((observed - simulated) ** 2 for observed, simulated in zip(obs_y, simulations[k]))
        for k in GRID
    }
    return min(GRID, key=lambda k: (errors[k], k)), errors


def clear_outputs():
    for path in (BEST, KS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def check_outputs(expected_k, obs_y, simulations):
    best, best_text = read_single_float(BEST)
    assert any(abs(best - k) < 1e-9 for k in GRID), f"best_k.txt contains non-grid value {best}"
    assert abs(best - expected_k) < 0.01, f"Expected best k {expected_k}, got {best}"

    ks_value, ks_text = read_single_float(KS)
    assert re.fullmatch(r"[+-]?(?:\d+\.\d{3}|\.\d{3})", ks_text), (
        "ks_dist.txt must be rounded and written with exactly 3 decimal places"
    )
    expected_ks = ks_2samp_stdlib(obs_y, simulations[expected_k])
    # Preserve the original numerical KS assertion and additionally enforce rounding.
    assert abs(ks_value - expected_ks) < 0.015, (
        f"Expected KS distance ~{expected_ks:.3f}, got {ks_value}"
    )
    assert abs(ks_value - round(expected_ks, 3)) < 0.00051, (
        f"KS value should round to {expected_ks:.3f}, got {ks_text}"
    )


def test_complete_solution():
    assert os.path.isfile(FIT), f"{FIT} is missing"
    assert os.access(FIT, os.X_OK), f"{FIT} is not executable"
    assert os.path.isfile(SIM), f"{SIM} is missing"
    assert os.access(SIM, os.X_OK), f"{SIM} is not executable"

    # Validate the repaired integrator independently against the exact ODE solution,
    # including the required upper stability limit k=2.0.
    for k in (0.1, 0.5, 1.5, 2.0):
        values = parse_simulator(k)
        for t, actual in enumerate(values):
            exact = 100.0 * math.exp(-k * (t + 1.0 - math.cos(t)))
            tolerance = max(0.03, 0.003 * abs(exact))
            assert abs(actual - exact) <= tolerance, (
                f"simulate.py is inaccurate at k={k}, t={t}: got {actual}, expected {exact}"
            )

    simulations = {k: parse_simulator(k) for k in GRID}
    original_observed = open(OBS, "rb").read()
    real_sim = SIM + ".verifier-real"
    state_path = "/tmp/fit_parallel_state.json"
    wrapped = False

    try:
        # Actually execute fit.sh on the supplied data and retain the original k=0.5 check.
        clear_outputs()
        run([FIT], timeout=90)
        original_rows = read_observed()
        original_y = [y for _, y in original_rows]
        expected_k, _ = expected_best(original_y, simulations)
        assert abs(expected_k - 0.5) < 0.01, f"Verifier fixture unexpectedly has best k {expected_k}"
        check_outputs(0.5, original_y, simulations)

        # Build a hidden perturbed data set. Its correct answer is derived here rather
        # than trusted, so fixed best_k/KS files cannot pass.
        rng = random.Random(secrets.randbits(64))
        for _ in range(100):
            target = rng.choice([k for k in GRID if k != 0.5])
            hidden_y = [
                max(0.0, y + rng.uniform(-1.25, 1.25))
                for y in simulations[target]
            ]
            hidden_y = [round(y, 4) for y in hidden_y]
            hidden_best, hidden_errors = expected_best(hidden_y, simulations)
            ordered = sorted(hidden_errors.values())
            if hidden_best != 0.5 and ordered[1] - ordered[0] > 0.01:
                break
        else:
            pytest.fail("Could not construct a discriminating hidden data set")

        with open(OBS, "w") as f:
            for t, y in enumerate(hidden_y):
                f.write(f"{t:.1f}\t{y:.4f}\n")

        # Interpose a behavior-preserving simulator wrapper. It records every grid
        # value and the maximum number of overlapping simulator processes.
        os.replace(SIM, real_sim)
        wrapped = True
        with open(state_path, "w") as f:
            json.dump({"active": 0, "maximum": 0, "args": []}, f)
        wrapper = textwrap.dedent(f'''\
            #!/usr/bin/env python3
            import fcntl, json, subprocess, sys, time
            state_path = {state_path!r}
            real_path = {real_sim!r}

            def update(delta):
                with open(state_path, "r+") as state_file:
                    fcntl.flock(state_file, fcntl.LOCK_EX)
                    try:
                        try:
                            state = json.load(state_file)
                        except Exception:
                            state = {{"active": 0, "maximum": 0, "args": []}}
                        if delta > 0:
                            state["active"] += 1
                            state["maximum"] = max(state["maximum"], state["active"])
                            state["args"].append(sys.argv[1:])
                        else:
                            state["active"] = max(0, state["active"] - 1)
                        state_file.seek(0)
                        state_file.truncate()
                        json.dump(state, state_file)
                        state_file.flush()
                    finally:
                        fcntl.flock(state_file, fcntl.LOCK_UN)

            update(1)
            try:
                time.sleep(0.25)
                result = subprocess.run([sys.executable, real_path] + sys.argv[1:],
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                sys.stdout.buffer.write(result.stdout)
                sys.stderr.buffer.write(result.stderr)
                raise SystemExit(result.returncode)
            finally:
                update(-1)
        ''')
        with open(SIM, "w") as f:
            f.write(wrapper)
        os.chmod(SIM, 0o755)

        clear_outputs()
        run([FIT], timeout=90)
        check_outputs(hidden_best, hidden_y, simulations)

        with open(state_path) as f:
            state = json.load(f)
        invoked = set()
        for args in state.get("args", []):
            if args:
                try:
                    invoked.add(round(float(args[0]), 1))
                except ValueError:
                    pass
        assert set(GRID).issubset(invoked), (
            f"fit.sh did not evaluate the complete 0.1..1.5 grid; observed {sorted(invoked)}"
        )
        assert state.get("maximum", 0) >= 2, (
            "fit.sh did not evaluate simulations in parallel (no overlapping runs observed)"
        )
    finally:
        with open(OBS, "wb") as f:
            f.write(original_observed)
        if wrapped:
            try:
                os.remove(SIM)
            except FileNotFoundError:
                pass
            if os.path.exists(real_sim):
                os.replace(real_sim, SIM)
        # Leave final artifacts corresponding to the original supplied data when possible.
        try:
            clear_outputs()
            subprocess.run([FIT], cwd=HOME, capture_output=True, text=True, timeout=90)
        except Exception:
            pass

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
