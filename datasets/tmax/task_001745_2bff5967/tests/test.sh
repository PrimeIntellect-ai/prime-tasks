#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import shutil
import subprocess
import time

import pytest

PROJECT_DIR = "/home/user/math_project"
SCRIPT_PATH = os.path.join(PROJECT_DIR, "run_pipeline.sh")

EXPECTED_SOURCES = {
    "math_ops.c": b'''#include <math.h>\n\ndouble compute_series(int n) {\n    double sum = 0.0;\n    for (int i = 1; i <= n; i++) {\n        sum += sin((double)i) * cos((double)i);\n    }\n    return sum;\n}\n''',
    "main.c": b'''#include <stdio.h>\n#include <stdlib.h>\n\nextern double compute_series(int n);\n\nint main(int argc, char *argv[]) {\n    if (argc != 2) return 1;\n    int n = atoi(argv[1]);\n    double result = compute_series(n);\n    printf("%.6f\\n", result);\n    return 0;\n}\n''',
}


def run_program(path, n):
    result = subprocess.run(
        [path, str(n)], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{path} failed for input {n}: return code {result.returncode}, "
        f"stderr: {result.stderr}"
    )
    return result.stdout


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    """Restore a clean project input, then run the submitted pipeline."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    # Confirm that the supplied inputs were not replaced, then restore the exact
    # initial layout so the verifier tests the pipeline rather than prebuilt files.
    for name, expected in EXPECTED_SOURCES.items():
        candidates = [
            os.path.join(PROJECT_DIR, name),
            os.path.join(PROJECT_DIR, "src", name),
        ]
        existing = [p for p in candidates if os.path.isfile(p)]
        assert existing, f"Provided source file {name} is missing."
        assert any(open(p, "rb").read() == expected for p in existing), (
            f"Provided source file {name} was modified."
        )

    for dirname in ["src", "bin", "results"]:
        path = os.path.join(PROJECT_DIR, dirname)
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.exists(path):
            os.unlink(path)

    for name, content in EXPECTED_SOURCES.items():
        with open(os.path.join(PROJECT_DIR, name), "wb") as f:
            f.write(content)

    start = time.time()
    result = subprocess.run(
        [SCRIPT_PATH], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=60
    )
    end = time.time()
    assert result.returncode == 0, (
        f"Script failed to execute properly. Stderr: {result.stderr}"
    )

    # Build an independent executable from verifier-owned source text. Its output
    # is the oracle; no expected answer is obtained from the submitted executable.
    oracle_src = "/tmp/calc_oracle.c"
    oracle_bin = "/tmp/calc_oracle"
    with open(oracle_src, "w") as f:
        f.write(r'''#include <math.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    double sum = 0.0;
    for (int i = 1; i <= n; i++)
        sum += sin((double)i) * cos((double)i);
    printf("%.6f\n", sum);
    return 0;
}
''')
    built = subprocess.run(
        ["gcc", oracle_src, "-o", oracle_bin, "-lm"],
        capture_output=True, text=True
    )
    assert built.returncode == 0, f"Failed to build verifier oracle: {built.stderr}"

    return {"start": start, "end": end, "oracle": oracle_bin}


def test_directories_created():
    for d in ["src", "bin", "results"]:
        path = os.path.join(PROJECT_DIR, d)
        assert os.path.isdir(path), f"Directory {path} was not created."


def test_source_files_moved():
    for f in ["main.c", "math_ops.c"]:
        old_path = os.path.join(PROJECT_DIR, f)
        new_path = os.path.join(PROJECT_DIR, "src", f)
        assert not os.path.exists(old_path), f"File {old_path} was not moved."
        assert os.path.isfile(new_path), f"File {new_path} does not exist in src directory."
        with open(new_path, "rb") as source_file:
            assert source_file.read() == EXPECTED_SOURCES[f], f"Source file {f} was modified."


def test_executable_compiled():
    bin_path = os.path.join(PROJECT_DIR, "bin", "calc")
    assert os.path.isfile(bin_path), f"Executable {bin_path} was not compiled."
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/calc is not a compiled ELF executable."


def test_executable_implements_algorithm(run_student_script):
    bin_path = os.path.join(PROJECT_DIR, "bin", "calc")
    oracle = run_student_script["oracle"]
    inputs = [0, 1, 17, 5000000]
    inputs.extend(secrets.randbelow(2000000) + 2 for _ in range(4))

    for n in inputs:
        actual = run_program(bin_path, n)
        expected = run_program(oracle, n)
        assert actual == expected, (
            f"calc produced {actual!r} for {n}, expected {expected!r}."
        )


def test_benchmark_file(run_student_script):
    bench_path = os.path.join(PROJECT_DIR, "results", "benchmark.txt")
    assert os.path.isfile(bench_path), f"Benchmark file {bench_path} does not exist."

    with open(bench_path, "r") as f:
        content = f.read()

    assert "real" in content, "Benchmark file missing 'real' timing."
    assert "user" in content, "Benchmark file missing 'user' timing."
    assert "sys" in content, "Benchmark file missing 'sys' timing."

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 3, "Benchmark must contain exactly the time -p timing lines."
    timing = re.compile(r"^(real|user|sys)\s+([0-9]+(?:\.[0-9]+)?)$")
    parsed = {}
    for line in lines:
        match = timing.fullmatch(line)
        assert match, f"Invalid time -p benchmark line: {line!r}"
        assert match.group(1) not in parsed, f"Duplicate {match.group(1)} timing line."
        parsed[match.group(1)] = float(match.group(2))
    assert set(parsed) == {"real", "user", "sys"}
    assert all(value >= 0 for value in parsed.values())

    mtime = os.path.getmtime(bench_path)
    assert run_student_script["start"] - 1 <= mtime <= run_student_script["end"] + 1, (
        "Benchmark file was not produced during this pipeline run."
    )


def test_encoded_output(run_student_script):
    b64_path = os.path.join(PROJECT_DIR, "results", "encoded_out.b64")
    assert os.path.isfile(b64_path), f"Encoded output file {b64_path} does not exist."

    with open(b64_path, "r") as f:
        encoded_content = f.read().strip()

    try:
        decoded_bytes = base64.b64decode(encoded_content, validate=True)
        decoded_text = decoded_bytes.decode("utf-8").strip()
    except Exception as e:
        pytest.fail(f"Failed to decode base64 content: {e}")

    expected_output = run_program(run_student_script["oracle"], 5000000).strip()
    assert decoded_text == expected_output, (
        f"Decoded output {decoded_text!r} does not match independently computed "
        f"expected output {expected_output!r}."
    )

    mtime = os.path.getmtime(b64_path)
    assert run_student_script["start"] - 1 <= mtime <= run_student_script["end"] + 1, (
        "Encoded output was not produced during this pipeline run."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
