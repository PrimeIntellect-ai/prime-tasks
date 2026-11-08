#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import shutil
import subprocess
import sys

import pytest

DIAGNOSTICS_FILE = "/home/user/diagnostics.txt"
PROJECT_DIR = "/home/user/optimization_project"
SUCCESS_REPORT = os.path.join(PROJECT_DIR, "SUCCESS_REPORT.txt")
SECRET = "sk-prod-ab9872jf9823kd"


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
        **kwargs,
    )


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_diagnostics():
    # Ensure the submitted setup.py really performs a clean extension build.
    shutil.rmtree(os.path.join(PROJECT_DIR, "build"), ignore_errors=True)
    for pattern in ("math_ext*.so", "math_ext*.pyd", "math_ext*.dylib"):
        for path in glob.glob(os.path.join(PROJECT_DIR, pattern)):
            os.remove(path)

    build = run([sys.executable, "setup.py", "build_ext", "--inplace"])
    assert re.search(r"(?:^|\s)-lm(?:\s|$)", build.stdout), (
        "The clean extension build did not link against the math library (-lm).\n"
        + build.stdout
    )

    artifacts = glob.glob(os.path.join(PROJECT_DIR, "math_ext*.so"))
    assert artifacts, "A clean build did not produce the math_ext shared library."
    with open(artifacts[0], "rb") as f:
        assert f.read(4) == b"\x7fELF", "math_ext is not a compiled ELF shared library."

    # Exercise the compiled function on values whose answers are calculated here.
    probe = (
        "import json, math, math_ext\n"
        "xs=[-3.125, -0.75, 0.0, 0.375, 2.625, 11.0]\n"
        "print(json.dumps([math_ext.fast_cos(x) for x in xs]))\n"
    )
    result = run([sys.executable, "-c", probe])
    import json
    actual = json.loads(result.stdout.strip().splitlines()[-1])
    points = [-3.125, -0.75, 0.0, 0.375, 2.625, 11.0]
    assert len(actual) == len(points)
    for x, got in zip(points, actual):
        assert math.isclose(got, math.cos(x), rel_tol=0.0, abs_tol=1e-12)

    # Remove any pre-created report and require run_diagnostics.py to make it anew.
    if os.path.exists(SUCCESS_REPORT):
        os.remove(SUCCESS_REPORT)
    run([sys.executable, "run_diagnostics.py"])
    assert os.path.isfile(SUCCESS_REPORT), (
        f"The file {SUCCESS_REPORT} does not exist. "
        "Did you run 'python3 run_diagnostics.py' after fixing the code?"
    )


def test_git_history_contains_recovered_secret():
    history = run(["git", "log", "--all", "-p", "--full-history"]).stdout
    assert SECRET in history, "The production API key was not found in the repository history."


def test_optimizer_derivative_and_convergence():
    code = (
        "import json, optimizer\n"
        "xs=[-2.75, -0.5, 0.0, 1.25, 3.5]\n"
        "root=optimizer.solve()\n"
        "print(json.dumps({'df':[optimizer.df(x) for x in xs], "
        "'root':root, 'residual':optimizer.f(root)}))\n"
    )
    import json
    data = json.loads(run([sys.executable, "-c", code]).stdout.strip().splitlines()[-1])
    points = [-2.75, -0.5, 0.0, 1.25, 3.5]
    for x, got in zip(points, data["df"]):
        assert math.isclose(got, 3 * x * x - 2, rel_tol=0.0, abs_tol=1e-12), (
            "optimizer.df does not implement the derivative 3*x**2 - 2."
        )
    assert abs(data["residual"]) < 1e-6, "optimizer.solve did not converge to a root."

    lo, hi = 2.0, 3.0
    for _ in range(100):
        mid = (lo + hi) / 2
        if mid**3 - 2 * mid - 5 > 0:
            hi = mid
        else:
            lo = mid
    expected = (lo + hi) / 2
    assert math.isclose(data["root"], expected, rel_tol=0.0, abs_tol=1e-6)


def test_diagnostics_file_exists():
    assert os.path.isfile(DIAGNOSTICS_FILE), f"The file {DIAGNOSTICS_FILE} does not exist."


def test_diagnostics_content():
    with open(DIAGNOSTICS_FILE, "r") as f:
        content = f.read()
    with open(SUCCESS_REPORT, "r") as f:
        report = f.read()

    # Retain the original secret, format, header, and root assertions.
    assert "sk-prod-ab9872jf9823kd" in content, (
        "The leaked API key 'sk-prod-ab9872jf9823kd' was not found in diagnostics.txt."
    )
    assert "SECRET_KEY: sk-prod-ab9872jf9823kd" in content, (
        "The SECRET_KEY format is incorrect in diagnostics.txt."
    )
    assert "DIAGNOSTICS:" in content, "The 'DIAGNOSTICS:' header is missing in diagnostics.txt."
    assert "Root: 2.09455" in content, (
        "The expected 'Root: 2.09455' was not found in diagnostics.txt. "
        "Did you fix the derivative in optimizer.py correctly?"
    )

    # The master report must contain exactly the freshly generated report.
    expected_master = f"SECRET_KEY: {SECRET}\nDIAGNOSTICS:\n{report}"
    assert content == expected_master, (
        "diagnostics.txt does not exactly contain the secret header followed by "
        "the complete, freshly generated SUCCESS_REPORT.txt."
    )

    match = re.fullmatch(r"Root: ([+-]?[0-9]+(?:\.[0-9]+)?)\nCos\(Root\): ([+-]?[0-9]+(?:\.[0-9]+)?)\n", report)
    assert match, "SUCCESS_REPORT.txt has an unexpected format."
    root_value, cos_value = map(float, match.groups())
    assert abs(root_value**3 - 2 * root_value - 5) < 1e-3
    assert math.isclose(cos_value, math.cos(root_value), rel_tol=0.0, abs_tol=1e-5)


def test_success_report_exists():
    assert os.path.isfile(SUCCESS_REPORT), (
        f"The file {SUCCESS_REPORT} does not exist. "
        "Did you run 'python3 run_diagnostics.py' after fixing the code?"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
