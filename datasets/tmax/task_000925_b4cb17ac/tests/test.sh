#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

PROJECT = Path("/home/user/qa_project")
SCRIPT = Path("/home/user/semver_match.sh")
ORCHESTRATOR = PROJECT / "run_e2e_tests.sh"


def test_pyproject_toml_valid_and_installable():
    """The metadata must parse and the project must actually install in a venv."""
    toml_path = PROJECT / "pyproject.toml"
    assert toml_path.is_file(), f"File {toml_path} is missing."

    if sys.version_info >= (3, 11):
        import tomllib
        with toml_path.open("rb") as f:
            try:
                tomllib.load(f)
            except Exception as e:
                pytest.fail(f"pyproject.toml is still invalid TOML: {e}")
    else:
        content = toml_path.read_text()
        assert "name =" in content or "name=" in content, "pyproject.toml seems to be missing basic metadata."

    with tempfile.TemporaryDirectory() as td:
        venv = Path(td) / "venv"
        made = subprocess.run(
            [sys.executable, "-m", "venv", str(venv)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
        assert made.returncode == 0, made.stdout
        python = venv / "bin" / "python"
        installed = subprocess.run(
            [str(python), "-m", "pip", "install", "."],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
        assert installed.returncode == 0, "python -m pip install . failed:\n" + installed.stdout
        imported = subprocess.run(
            [str(python), "-c", "import qa_project"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )
        assert imported.returncode == 0, "Installed package could not be imported:\n" + imported.stdout


def test_run_e2e_tests_updated_and_executed():
    """Keep the source checks and prove that the orchestrator invokes the replacement."""
    assert ORCHESTRATOR.is_file(), f"File {ORCHESTRATOR} is missing."
    content = ORCHESTRATOR.read_text()
    assert "/app/legacy_resolver" not in content, "run_e2e_tests.sh still references the legacy binary /app/legacy_resolver."
    assert "semver_match.sh" in content, "run_e2e_tests.sh does not reference the new semver_match.sh script."
    assert os.access(ORCHESTRATOR, os.X_OK), "run_e2e_tests.sh is not executable."
    assert SCRIPT.is_file(), f"File {SCRIPT} is missing."

    marker = Path("/tmp/orchestrator_called_semver")
    backup = Path("/tmp/semver_match.agent_backup")
    marker.unlink(missing_ok=True)
    backup.unlink(missing_ok=True)
    SCRIPT.rename(backup)
    try:
        SCRIPT.write_text("#!/bin/bash\nprintf '%s\\n' \"$*\" >> /tmp/orchestrator_called_semver\nexit 0\n")
        SCRIPT.chmod(0o755)
        result = subprocess.run(
            [str(ORCHESTRATOR)],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, "run_e2e_tests.sh failed:\n" + result.stdout
        assert marker.is_file() and marker.read_text().strip(), "run_e2e_tests.sh did not actually invoke semver_match.sh."
    finally:
        SCRIPT.unlink(missing_ok=True)
        backup.rename(SCRIPT)
        marker.unlink(missing_ok=True)


def parse_version(value):
    value = value.split("+", 1)[0]
    match = re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?", value)
    if not match:
        raise ValueError(value)
    pre = None if match.group(4) is None else match.group(4).split(".")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)), pre)


def compare_versions(left, right):
    a, b = parse_version(left), parse_version(right)
    if a[:3] != b[:3]:
        return -1 if a[:3] < b[:3] else 1
    ap, bp = a[3], b[3]
    if ap is None or bp is None:
        if ap is None and bp is None:
            return 0
        return 1 if ap is None else -1
    for x, y in zip(ap, bp):
        if x == y:
            continue
        xn, yn = x.isdigit(), y.isdigit()
        if xn and yn:
            return -1 if int(x) < int(y) else 1
        if xn != yn:
            return -1 if xn else 1
        return -1 if x < y else 1
    if len(ap) == len(bp):
        return 0
    return -1 if len(ap) < len(bp) else 1


def eval_comparator(op, reference, target):
    cmp = compare_versions(target, reference)
    return {
        "=": cmp == 0,
        "!=": cmp != 0,
        ">": cmp > 0,
        ">=": cmp >= 0,
        "<": cmp < 0,
        "<=": cmp <= 0,
    }[op]


def tokenize(expression):
    pattern = re.compile(r"\s*(>=|<=|!=|=|>|<|&&|\|\||\(|\)|[0-9A-Za-z.+-]+)")
    tokens, pos = [], 0
    while pos < len(expression):
        match = pattern.match(expression, pos)
        if not match:
            raise ValueError(expression[pos:])
        tokens.append(match.group(1))
        pos = match.end()
    return tokens


def evaluate_expression(expression, target):
    tokens = tokenize(expression)
    pos = 0

    def atom():
        nonlocal pos
        if pos < len(tokens) and tokens[pos] == "(":
            pos += 1
            value = disjunction()
            assert pos < len(tokens) and tokens[pos] == ")"
            pos += 1
            return value
        assert pos + 1 < len(tokens) and tokens[pos] in {"=", "!=", ">", ">=", "<", "<="}
        op, ref = tokens[pos], tokens[pos + 1]
        pos += 2
        return eval_comparator(op, ref, target)

    def conjunction():
        nonlocal pos
        value = atom()
        while pos < len(tokens) and tokens[pos] == "&&":
            pos += 1
            rhs = atom()
            value = value and rhs
        return value

    def disjunction():
        nonlocal pos
        value = conjunction()
        while pos < len(tokens) and tokens[pos] == "||":
            pos += 1
            rhs = conjunction()
            value = value or rhs
        return value

    result = disjunction()
    assert pos == len(tokens)
    return result


def test_semver_match_accuracy():
    """Exercise the submitted Bash artifact against independently derived answers."""
    assert SCRIPT.is_file(), f"File {SCRIPT} is missing."
    assert not SCRIPT.is_symlink(), "semver_match.sh must be a submitted Bash script, not a symlink."
    assert os.access(SCRIPT, os.X_OK), "semver_match.sh is not executable."
    data = SCRIPT.read_bytes()
    assert b"\x00" not in data, "semver_match.sh is not a text Bash script."
    first_line = data.splitlines()[0].decode("utf-8", "replace") if data else ""
    assert first_line.startswith("#!") and "bash" in first_line, "semver_match.sh must have a Bash shebang."

    for args in ([], [">=1.0.0"]):
        result = subprocess.run([str(SCRIPT), *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        assert result.returncode != 0, "semver_match.sh must reject an incorrect argument count."

    fixed = [
        (">=1.0.0", "1.0.0"),
        (">1.0.0", "1.0.0"),
        ("<2.0.0 && >=1.2.0", "1.9.9"),
        ("<1.0.0 || >=2.0.0 && <3.0.0", "2.5.0"),
        ("(<1.0.0 || >=2.0.0) && <3.0.0", "1.5.0"),
        ("=1.2.3+build.9", "1.2.3+other"),
        (">=1.0.0-alpha && <1.0.0", "1.0.0-beta.2"),
        (">1.0.0-beta.2", "1.0.0-beta.11"),
        ("!=2.0.0-rc1", "2.0.0-rc1"),
        ("(>=0.1.0&&<0.2.0)||(>=3.0.0&&<=3.4.5)", "3.4.5"),
    ]

    rng = random.SystemRandom()
    versions = [
        "0.0.0", "0.1.0", "0.9.9", "1.0.0-alpha", "1.0.0-alpha.1",
        "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
        "1.2.3", "1.2.3+build.7", "2.0.0-rc1", "2.0.0", "3.4.5", "10.2.1",
    ]
    ops = [">", "<", ">=", "<=", "=", "!="]

    def leaf():
        return f"{rng.choice(ops)}{rng.choice(versions)}"

    generated = []
    for _ in range(240):
        count = rng.randint(2, 5)
        expression = leaf()
        for _ in range(count - 1):
            rhs = leaf()
            boolean = rng.choice([" && ", " || "])
            if rng.random() < 0.55:
                expression = f"({expression}{boolean}{rhs})"
            else:
                expression = expression + boolean + rhs
        generated.append((expression, rng.choice(versions)))

    cases = fixed + generated
    matches = 0
    failures = []
    for expression, version in cases:
        expected = evaluate_expression(expression, version)
        try:
            result = subprocess.run(
                [str(SCRIPT), expression, version],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=2,
            )
            actual = result.returncode == 0
        except subprocess.TimeoutExpired:
            actual = None
        if actual == expected:
            matches += 1
        elif len(failures) < 8:
            failures.append(f"{expression!r} with {version!r}: expected {expected}, got {actual}")

    accuracy = matches / len(cases)
    assert accuracy >= 0.95, f"Accuracy {accuracy:.2f} is below 0.95. Examples: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
