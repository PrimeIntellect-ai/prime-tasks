#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

TARGET = "/app/artifact-filter/filter"


def run_filter(executable, path, timeout=2):
    try:
        return subprocess.run(
            [executable, str(path)], capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"filter timed out on {path}")


def assert_classification(executable, path, expected):
    result = run_filter(executable, path)
    assert result.stdout in (expected, expected + "\n"), (
        f"{path} expected exactly {expected!r}, got stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}, exit={result.returncode}"
    )


def test_filter_executable_exists():
    """Ensure the target executable exists and is executable."""
    assert os.path.exists(TARGET), f"Target executable {TARGET} does not exist. Did you compile it?"
    assert os.access(TARGET, os.X_OK), f"Target executable {TARGET} is not executable."


def test_adversarial_corpus():
    """Retain the original clean and evil corpus assertions."""
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.art"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.art"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for fpath in clean_files:
        try:
            result = subprocess.run([TARGET, fpath], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "ACCEPT":
                clean_failed.append((os.path.basename(fpath), output))
        except subprocess.TimeoutExpired:
            clean_failed.append((os.path.basename(fpath), "TIMEOUT (infinite loop?)"))
        except Exception as e:
            clean_failed.append((os.path.basename(fpath), f"ERROR: {str(e)}"))

    evil_failed = []
    for fpath in evil_files:
        try:
            result = subprocess.run([TARGET, fpath], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "REJECT":
                evil_failed.append((os.path.basename(fpath), output))
        except subprocess.TimeoutExpired:
            evil_failed.append((os.path.basename(fpath), "TIMEOUT (infinite loop?)"))
        except Exception as e:
            evil_failed.append((os.path.basename(fpath), f"ERROR: {str(e)}"))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed:")
        for fname, out in evil_failed:
            errors.append(f"  - {fname} (Output: {out})")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected:")
        for fname, out in clean_failed:
            errors.append(f"  - {fname} (Output: {out})")
    if errors:
        pytest.fail("\n".join(errors))


def test_vendored_parser_merge_transition_is_fixed():
    """Exercise the actual vendored package and ensure parsing continues after MERGE."""
    with tempfile.TemporaryDirectory(prefix="parser-check-") as td:
        root = Path(td)
        (root / "go.mod").write_text(
            "module parsercheck\n\ngo 1.18\n\nrequire artparse v0.0.0\n"
            "replace artparse => /app/vendored/artparse\n"
        )
        (root / "main.go").write_text(r'''package main
import (
    "fmt"
    "os"
    "artparse"
)
func main() {
    a, err := artparse.Parse("NAME Probe\nMERGE DepOne\nMERGE DepTwo\nLINK out/bin\n")
    if err != nil || a == nil || a.Name != "Probe" || len(a.Merges) != 2 || a.Merges[0] != "DepOne" || a.Merges[1] != "DepTwo" || len(a.Links) != 1 || a.Links[0] != "out/bin" {
        fmt.Fprintln(os.Stderr, "unexpected parse result")
        os.Exit(1)
    }
}
''')
        result = subprocess.run(
            ["go", "run", "."], cwd=root, capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, result.stdout + result.stderr


@pytest.fixture(scope="session")
def rebuilt_filter():
    """Build the submitted source and verify that its package depends on artparse."""
    project = Path("/app/artifact-filter")
    assert (project / "main.go").is_file(), "/app/artifact-filter/main.go is missing"

    deps = subprocess.run(
        ["go", "list", "-deps", "."], cwd=project,
        capture_output=True, text=True, timeout=15
    )
    assert deps.returncode == 0, deps.stdout + deps.stderr
    assert "artparse" in deps.stdout.splitlines(), "artifact-filter does not import artparse"

    output = Path(tempfile.mkdtemp(prefix="rebuilt-filter-")) / "filter"
    built = subprocess.run(
        ["go", "build", "-o", str(output), "."], cwd=project,
        capture_output=True, text=True, timeout=20
    )
    assert built.returncode == 0, built.stdout + built.stderr
    assert output.is_file() and os.access(output, os.X_OK)
    return str(output)


def test_randomized_and_malformed_inputs(rebuilt_filter):
    """Use unpredictable paths and contents so pathname-based classifiers cannot pass."""
    token = secrets.token_hex(10)
    a = "Artifact_" + secrets.token_hex(6)
    b = "Dependency_" + secrets.token_hex(6)
    c = "Library_" + secrets.token_hex(6)

    with tempfile.TemporaryDirectory(prefix="art-cases-") as td:
        root = Path(td)
        cases = []

        def add(label, data, expected, binary=False):
            path = root / f"{secrets.token_hex(8)}-{label}.art"
            if binary:
                path.write_bytes(data)
            else:
                path.write_text(data)
            cases.append((path, expected))

        add("ordinary", f"NAME {a}\nMERGE {b}\nMERGE {c}\nLINK output/{token}/bin\n", "ACCEPT")
        add("no-merge", f"NAME {a}\nLINK build/{token}/result\n", "ACCEPT")
        add("self-cycle", f"NAME {a}\nMERGE {a}\nLINK output/bin\n", "REJECT")
        add("long-cycle", f"NAME {a}\nMERGE {b}\nNAME {b}\nMERGE {c}\nNAME {c}\nMERGE {a}\n", "REJECT")
        add("absolute", f"NAME {a}\nMERGE {b}\nLINK /var/tmp/{token}\n", "REJECT")
        add("traversal-one", f"NAME {a}\nLINK ../{token}\n", "REJECT")
        add("traversal-deep", f"NAME {a}\nLINK safe/../../../{token}\n", "REJECT")
        add("malformed-unknown", f"NAME {a}\nTHIS_IS_NOT_A_DIRECTIVE {token}\n", "REJECT")
        add("malformed-binary", b"NAME Broken\nLINK out/bin\n\xff\xfe\x00\n", "REJECT", binary=True)
        add("malformed-empty", "", "REJECT")

        # Test both the required installed executable and a fresh build from main.go.
        for executable in (TARGET, rebuilt_filter):
            for path, expected in cases:
                assert_classification(executable, path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
