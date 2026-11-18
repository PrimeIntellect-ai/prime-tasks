#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

SCRIPT_PATH = "/home/user/deterministic_integrate.sh"
SAMPLES_PATH = "/home/user/samples.txt"
LOG_PATH = "/home/user/convergence.log"


def compute_expected_log():
    if not os.path.exists(SAMPLES_PATH):
        return []

    with open(SAMPLES_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = []
    for n in [1000, 2000, 3000, 4000, 5000]:
        subset = lines[:n]
        chunks = [subset[i:i + 1000] for i in range(0, len(subset), 1000)]
        partial_sums = []
        for chunk in chunks:
            chunk_sum = sum(math.exp(-(float(x) ** 2) / 2) for x in chunk)
            partial_sums.append(float(f"{chunk_sum:.15f}"))
        final_sum = sum(partial_sums)
        expected.append(f"{n} {final_sum:.15f}")
    return expected


def reference_result(lines):
    partials = []
    with tempfile.TemporaryDirectory(prefix="verifier_reference_") as d:
        for index in range(0, len(lines), 1000):
            chunk = Path(d) / f"chunk_{index // 1000:06d}"
            chunk.write_text("".join(f"{x}\n" for x in lines[index:index + 1000]))
            result = subprocess.run(
                ["/usr/bin/awk", "{s+=exp(-$1*$1/2)} END {printf \"%.15f\\n\", s}", str(chunk)],
                text=True,
                capture_output=True,
                check=True,
            )
            partials.append(result.stdout.strip())

    result = subprocess.run(
        ["/usr/bin/awk", "{s+=$1} END {printf \"%.15f\\n\", s}"],
        input="".join(f"{p}\n" for p in partials),
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def filesystem_paths(roots):
    found = set()
    for root in roots:
        root_path = Path(root)
        if not root_path.exists():
            continue
        for directory, dirs, files in os.walk(root, followlinks=False):
            for name in dirs + files:
                found.add(os.path.join(directory, name))
    return found


def run_case(count):
    # Generated after the agent runs, so the submission cannot hard-code answers.
    rng = secrets.SystemRandom()
    lines = [f"{rng.uniform(-9.0, 9.0):.12f}" for _ in range(count)]
    expected = reference_result(lines)

    with tempfile.TemporaryDirectory(prefix="integration_case_") as work:
        input_path = Path(work) / "input.txt"
        input_path.write_text("".join(f"{x}\n" for x in lines))
        roots = [work, "/tmp", "/home/user"]
        before = filesystem_paths(roots)
        env = os.environ.copy()
        env["TMPDIR"] = work

        result = subprocess.run(
            [SCRIPT_PATH, str(input_path)],
            cwd=work,
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        after = filesystem_paths(roots)

        assert result.returncode == 0, result.stderr
        assert result.stderr == "", f"Unexpected stderr: {result.stderr!r}"
        assert re.fullmatch(r"-?\d+\.\d{15}\n", result.stdout), \
            f"Script must print only one value with 15 decimal places, got {result.stdout!r}"
        assert result.stdout.strip() == expected, \
            f"Expected {expected}, got {result.stdout.strip()} for {count} input lines"
        assert after - before == set(), f"Temporary files were not cleaned up: {sorted(after - before)}"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_parallel_constructs():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "&" in content, f"Script {SCRIPT_PATH} does not contain '&' for background jobs."
    assert "wait" in content, f"Script {SCRIPT_PATH} does not contain 'wait' command."


def test_convergence_log_matches():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = compute_expected_log()
    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in {LOG_PATH}, found {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i + 1} mismatch: expected '{expected}', got '{actual}'."


def test_executes_correctly_on_unseen_inputs_and_cleans_up():
    run_case(137)
    run_case(2507)
    # Exercise many chunks and repeat to expose completion-order reductions.
    run_case(12037)
    run_case(12037)


def test_requires_exactly_one_filename_argument():
    no_arg = subprocess.run([SCRIPT_PATH], text=True, capture_output=True, timeout=5)
    assert no_arg.returncode != 0, "Script must reject a missing filename argument."

    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write("0.0\n")
        name = f.name
    try:
        extra_arg = subprocess.run([SCRIPT_PATH, name, name], text=True, capture_output=True, timeout=5)
        assert extra_arg.returncode != 0, "Script must reject extra arguments."
    finally:
        os.unlink(name)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
