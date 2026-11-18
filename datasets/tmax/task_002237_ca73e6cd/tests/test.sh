#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import time
from pathlib import Path

import pytest

legacy_bin = "/app/legacy_resolver"
fast_bin = "/home/user/fast_resolver"
test_dir = "/app/hidden_test_graphs"


def test_fast_resolver_exists():
    """Check that the fast resolver binary was compiled and is executable."""
    assert os.path.isfile(fast_bin), f"Fast resolver binary {fast_bin} does not exist. Did you compile it?"
    assert os.access(fast_bin, os.X_OK), f"Fast resolver binary {fast_bin} is not executable."
    with open(fast_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Fast resolver must be a compiled ELF binary."
    with open(fast_bin, "rb") as candidate, open(legacy_bin, "rb") as legacy:
        assert candidate.read() != legacy.read(), "Fast resolver must not be a copy of the legacy binary."


def test_accuracy_and_speedup():
    """Retain the original oracle-equivalence and performance assertions."""
    assert os.path.isdir(test_dir), f"Test directory {test_dir} does not exist."
    test_files = [f for f in os.listdir(test_dir) if os.path.isfile(os.path.join(test_dir, f))]
    assert len(test_files) > 0, "No test graphs found."

    correct = 0
    total = 0
    legacy_time = 0.0
    fast_time = 0.0

    for filename in test_files:
        filepath = os.path.join(test_dir, filename)

        t0 = time.time()
        try:
            leg_out = subprocess.check_output([legacy_bin, filepath], text=True, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as e:
            leg_out = e.output
        t1 = time.time()
        legacy_time += t1 - t0

        t0 = time.time()
        try:
            fast_out = subprocess.check_output(
                [fast_bin, filepath], text=True, timeout=5.0, stderr=subprocess.STDOUT
            )
        except subprocess.TimeoutExpired:
            fast_out = "TIMEOUT"
        except subprocess.CalledProcessError as e:
            fast_out = e.output
        except Exception:
            fast_out = "ERROR"
        t1 = time.time()
        fast_time += t1 - t0

        if leg_out.strip() == fast_out.strip():
            correct += 1
        total += 1

    accuracy = correct / total
    speedup = legacy_time / fast_time if fast_time > 0 else 0.0

    assert accuracy >= 1.0, f"Accuracy is {accuracy*100:.2f}%, expected 100.0% match with legacy resolver."
    assert speedup >= 20.0, f"Speedup is {speedup:.2f}x, expected at least 20.0x."


def _name(prefix):
    return prefix + secrets.token_hex(6)


def _graph(records):
    records = list(records)
    random.SystemRandom().shuffle(records)
    return "\n\n".join(
        f"PKG {name} {version}\nREQUIRES {requires}"
        for name, version, requires in records
    ) + "\n"


def _run(path):
    try:
        return subprocess.run(
            [fast_bin, str(path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=2.0,
            check=False,
        ).stdout.strip()
    except subprocess.TimeoutExpired:
        pytest.fail(f"Resolver timed out on generated graph {path}")


def _assert_install_order(output, expected):
    assert output not in {"UNSATISFIABLE", "CIRCULAR_DEPENDENCY"}, (
        f"Expected a valid installation order {expected}, got {output!r}"
    )
    pattern = re.compile(r"(?<![A-Za-z0-9_])(?:" + "|".join(
        re.escape(n) for n in sorted(expected, key=len, reverse=True)
    ) + r")(?![A-Za-z0-9_])")
    observed = pattern.findall(output)
    assert observed == expected, f"Expected installation order {expected}, got {output!r}"


def test_generated_semantics_and_cycles(tmp_path):
    """Exercise parsing, SemVer, dependency resolution, and cycle detection on fresh inputs."""
    cases = []

    # A basic package with no dependencies must be installable.
    a = _name("Solo")
    cases.append((_graph([(a, "1.0.0", "None")]), "ORDER", [a]))

    # Nested parentheses and AND, with a uniquely determined topological order.
    a, b, c = _name("App"), _name("Lib"), _name("Core")
    cases.append((_graph([
        (a, "3.0.0", f"((((({b} (>= 1.0.0)))) AND (({c} (= 2.0.0)))))"),
        (b, "1.4.0", f"(({c} (>= 2.0.0)))"),
        (c, "2.0.0", "None"),
    ]), "ORDER", [c, b, a]))

    # Nested OR: the first branch is impossible and the second branch is valid.
    a, b, c, missing = _name("Root"), _name("Mid"), _name("Leaf"), _name("Missing")
    cases.append((_graph([
        (a, "1.0.0", f"(({missing} (= 9.9.9) AND {b} (= 1.0.0)) OR (({b} (= 1.0.0) AND ({c} (>= 1.0.0)))))"),
        (b, "1.0.0", f"{c} (= 1.0.0)"),
        (c, "1.0.0", "None"),
    ]), "ORDER", [c, b, a]))

    # SemVer prerelease identifiers compare numerically where appropriate.
    for installed, constraint in [
        ("1.0.0", "> 1.0.0-alpha"),
        ("1.0.0-alpha.10", "> 1.0.0-alpha.2"),
        ("1.0.0-beta", "> 1.0.0-alpha.10"),
        ("1.0.0-alpha", "> 1.0.0-1"),
        ("1.2.3+build.7", "= 1.2.3+other"),
    ]:
        app, dep = _name("SemApp"), _name("SemLib")
        cases.append((_graph([
            (app, "2.0.0", f"{dep} ({constraint})"),
            (dep, installed, "None"),
        ]), "ORDER", [dep, app]))

    # False constraints and missing packages are unsatisfiable.
    for installed, constraint in [
        ("1.0.0-alpha", ">= 1.0.0"),
        ("1.0.0", "< 1.0.0-alpha"),
        ("2.0.0", "< 2.0.0"),
    ]:
        app, dep = _name("BadApp"), _name("BadLib")
        cases.append((_graph([
            (app, "1.0.0", f"{dep} ({constraint})"),
            (dep, installed, "None"),
        ]), "UNSATISFIABLE", None))

    app, dep, missing = _name("BoolApp"), _name("BoolLib"), _name("Absent")
    cases.append((_graph([
        (app, "1.0.0", f"(({dep} (> 9.0.0) OR ({missing} (= 1.0.0))) AND ({dep} (= 1.5.0)))"),
        (dep, "1.5.0", "None"),
    ]), "UNSATISFIABLE", None))

    # Direct, indirect, and self cycles must terminate and report a cycle.
    a, b = _name("CycleA"), _name("CycleB")
    cases.append((_graph([
        (a, "1.0.0", f"{b} (= 1.0.0)"),
        (b, "1.0.0", f"{a} (= 1.0.0)"),
    ]), "CIRCULAR_DEPENDENCY", None))

    a, b, c = _name("RingA"), _name("RingB"), _name("RingC")
    cases.append((_graph([
        (a, "1.0.0", f"{b} (>= 1.0.0)"),
        (b, "1.0.0", f"{c} (>= 1.0.0)"),
        (c, "1.0.0", f"{a} (>= 1.0.0)"),
    ]), "CIRCULAR_DEPENDENCY", None))

    a = _name("SelfCycle")
    cases.append((_graph([(a, "1.0.0", f"(({a} (= 1.0.0)))")]), "CIRCULAR_DEPENDENCY", None))

    random.SystemRandom().shuffle(cases)
    for index, (content, expected_kind, expected_order) in enumerate(cases):
        path = tmp_path / f"graph_{secrets.token_hex(10)}_{index}.txt"
        path.write_text(content)
        output = _run(path)
        if expected_kind == "ORDER":
            _assert_install_order(output, expected_order)
        else:
            assert output == expected_kind, (
                f"Expected {expected_kind}, got {output!r} for graph:\n{content}"
            )


def test_requires_exactly_one_argument():
    no_arg = subprocess.run([fast_bin], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2.0)
    two_args = subprocess.run(
        [fast_bin, "/dev/null", "/dev/null"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2.0,
    )
    assert no_arg.returncode != 0, "Resolver must reject invocation without an input path."
    assert two_args.returncode != 0, "Resolver must reject invocation with more than one input path."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
