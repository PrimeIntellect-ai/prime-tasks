#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import secrets
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/mcmc_Z.c"
SCRIPT = "/home/user/build_and_run.sh"
RESULT = "/home/user/result.txt"


@pytest.fixture(scope="session", autouse=True)
def run_submitted_build():
    assert os.path.isfile(SOURCE), "The file /home/user/mcmc_Z.c does not exist."
    assert os.path.isfile(SCRIPT), f"The file {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"The file {SCRIPT} is not executable."

    # Do not allow a pre-created result or executable to satisfy the tests.
    for path in (RESULT, "/home/user/mcmc_Z"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = subprocess.run(
        [SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert proc.returncode == 0, f"build_and_run.sh failed:\n{proc.stdout}"
    assert os.path.isfile("/home/user/mcmc_Z"), "The build script did not create /home/user/mcmc_Z."
    assert os.access("/home/user/mcmc_Z", os.X_OK), "The built mcmc_Z is not executable."


def test_mcmc_c_exists():
    assert os.path.isfile(SOURCE), "The file /home/user/mcmc_Z.c does not exist."


def test_build_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"The file {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"The file {SCRIPT} is not executable."


def test_result_file_exists():
    assert os.path.isfile(RESULT), "The file /home/user/result.txt does not exist."


def test_result_content():
    with open(RESULT, "r") as f:
        content = f.read().strip()

    expected = "Z_val: 0.501253"
    assert expected in content, f"Expected '{expected}' in /home/user/result.txt, but got: {content}"
    assert content == expected, f"result.txt must contain exactly '{expected}', but got: {content}"


def _without_comments(text):
    text = re.sub(r'/\\*.*?\\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\\n]*', '', text)
    return text


def _integrate_body(text):
    match = re.search(
        r'\\bdouble\\s+integrate_Z\\s*\\(\\s*double\\s+\\w+\\s*\\)\\s*\\{', text
    )
    assert match, "Could not find the required double integrate_Z(double theta) function."
    start = match.end() - 1
    depth = 0
    for pos in range(start, len(text)):
        if text[pos] == '{':
            depth += 1
        elif text[pos] == '}':
            depth -= 1
            if depth == 0:
                return text[start + 1:pos]
    raise AssertionError("The integrate_Z function has unbalanced braces.")


def test_kahan_summation_implemented():
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original heuristic assertion.
    pattern = re.compile(r'\\b(c|err|comp|y|t)\\s*[-+*\\/]?=', re.IGNORECASE)
    has_compensation = pattern.search(content) is not None
    assert has_compensation, "Could not find evidence of Kahan summation (e.g. compensation variable updates) in /home/user/mcmc_Z.c."

    body = _integrate_body(_without_comments(content))
    assert re.search(r'\\b(for|while)\\s*\\(', body), "integrate_Z must perform the numerical integration in a loop."

    # Require the connected four-step Kahan recurrence, allowing arbitrary
    # identifier names and declarations rather than merely any assignment.
    first_steps = re.finditer(
        r'(?:\\bdouble\\s+)?(?P<y>[A-Za-z_]\\w*)\\s*=\\s*[^;]+?\\s*-\\s*(?P<c>[A-Za-z_]\\w*)\\s*;',
        body,
    )
    found = False
    for first in first_steps:
        y, comp = first.group('y'), first.group('c')
        tail = body[first.end():]
        second = re.search(
            r'(?:\\bdouble\\s+)?(?P<t>[A-Za-z_]\\w*)\\s*=\\s*(?P<s>[A-Za-z_]\\w*)\\s*\\+\\s*' + re.escape(y) + r'\\s*;',
            tail,
        )
        if not second:
            continue
        total, updated = second.group('s'), second.group('t')
        tail2 = tail[second.end():]
        correction = re.search(
            re.escape(comp) + r'\\s*=\\s*\\(?\\s*' + re.escape(updated) +
            r'\\s*-\\s*' + re.escape(total) + r'\\s*\\)?\\s*-\\s*' + re.escape(y) + r'\\s*;',
            tail2,
        )
        if not correction:
            continue
        tail3 = tail2[correction.end():]
        if re.search(re.escape(total) + r'\\s*=\\s*' + re.escape(updated) + r'\\s*;', tail3):
            found = True
            break

    assert found, "integrate_Z does not contain a connected Kahan compensation recurrence inside its integration code."


def _reference_trapezoid(theta):
    n = 1_000_000
    dx = 1.0e-5
    total = 0.0
    compensation = 0.0
    for i in range(n + 1):
        term = math.exp(-(i * dx) * theta)
        if i == 0 or i == n:
            term *= 0.5
        corrected = term - compensation
        updated = total + corrected
        compensation = (updated - total) - corrected
        total = updated
    return total * dx


def test_integrate_Z_on_derived_inputs():
    # Include the submission in a wrapper so even a file-local integrate_Z can
    # be called, while renaming its main function to avoid a collision.
    with tempfile.TemporaryDirectory() as td:
        wrapper = os.path.join(td, "wrapper.c")
        library = os.path.join(td, "submission.so")
        with open(wrapper, "w") as f:
            f.write('#define main submitted_main\\n')
            f.write('#include "/home/user/mcmc_Z.c"\\n')
            f.write('#undef main\\n')
            f.write('double call_integrate(double theta) { return integrate_Z(theta); }\\n')

        proc = subprocess.run(
            ["gcc", "-O3", "-fPIC", "-shared", "-o", library, wrapper, "-lm"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
        )
        assert proc.returncode == 0, f"Could not compile mcmc_Z.c for behavioral testing:\n{proc.stdout}"

        lib = ctypes.CDLL(library)
        call = lib.call_integrate
        call.argtypes = [ctypes.c_double]
        call.restype = ctypes.c_double

        rng = secrets.SystemRandom()
        thetas = [rng.uniform(5.0, 15.0) for _ in range(3)]
        for theta in thetas:
            expected = _reference_trapezoid(theta)
            actual = call(theta)
            assert math.isfinite(actual), f"integrate_Z({theta}) returned a non-finite value."
            tolerance = max(3.0e-12, 16.0 * math.ulp(expected))
            assert abs(actual - expected) <= tolerance, (
                f"integrate_Z({theta}) returned {actual}, but the N=1,000,000 "
                f"Kahan trapezoidal result is {expected}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
