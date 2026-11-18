#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

NUMBER_RE = re.compile(r'^[0-9]+(\.[0-9]+)?$')


def test_cpp_source_exists():
    path = "/home/user/reducer.cpp"
    assert os.path.isfile(path), f"{path} does not exist."


def test_executable_exists():
    path = "/home/user/reducer"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_reduced_csv_content():
    path = "/home/user/reduced.csv"
    assert os.path.isfile(path), f"{path} does not exist."

    expected = """3,7,11,15,19
30,70,110,150,190
0,7,6,7,9
0,0,0,0,0
0,0,0,0,0
1000,2000,3000,4000,5000"""

    with open(path, "r") as f:
        actual = f.read().strip()

    assert actual == expected, "The contents of reduced.csv do not match the expected dimensionality reduction and imputation."


def test_benchmark_txt():
    path = "/home/user/benchmark.txt"
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert NUMBER_RE.match(content), f"benchmark.txt does not contain a valid number, got: {content}"


def encode_case(rows):
    input_lines = []
    output_lines = []
    for row in rows:
        assert len(row) == 10
        input_lines.append(",".join("" if value is None else str(value) for value in row))
        values = [0 if value is None else value for value in row]
        output_lines.append(",".join(str(values[i] + values[i + 1]) for i in range(0, 10, 2)))
    return "\n".join(input_lines) + "\n", "\n".join(output_lines)


def run_case(executable, rows, require_positive_benchmark=False):
    dataset_text, expected = encode_case(rows)
    Path("/home/user/dataset.csv").write_text(dataset_text)

    for output in ("/home/user/reduced.csv", "/home/user/benchmark.txt"):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )

    assert os.path.isfile("/home/user/reduced.csv"), "Execution did not create reduced.csv."
    actual = Path("/home/user/reduced.csv").read_text().strip()
    assert actual == expected, "The executable produced incorrect output for an altered dataset."

    assert os.path.isfile("/home/user/benchmark.txt"), "Execution did not create benchmark.txt."
    benchmark = Path("/home/user/benchmark.txt").read_text().strip()
    assert NUMBER_RE.fullmatch(benchmark), f"Execution wrote an invalid benchmark value: {benchmark}"
    if require_positive_benchmark:
        assert float(benchmark) > 0, "Processing a large dataset must produce a positive elapsed time."


def test_pipeline_executes_on_altered_inputs_and_source_builds():
    tracked = [
        "/home/user/dataset.csv",
        "/home/user/reduced.csv",
        "/home/user/benchmark.txt",
    ]
    saved = {path: Path(path).read_bytes() if os.path.exists(path) else None for path in tracked}

    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_reducer_", dir="/tmp")
    os.close(fd)
    os.remove(rebuilt)

    try:
        compile_result = subprocess.run(
            ["g++", "-O3", "-std=c++17", "/home/user/reducer.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "reducer.cpp does not compile with g++ -O3 -std=c++17: "
            + compile_result.stderr.decode(errors="replace")
        )

        rng = secrets.SystemRandom()
        random_rows = [
            [None, 8, -3, None, 0, 11, None, None, -9, 4],
            [None] * 10,
            [7, None, None, -7, 13, 14, -20, None, None, 1],
        ]
        for row_index in range(37):
            row = []
            for column in range(10):
                if rng.randrange(5) == 0:
                    row.append(None)
                else:
                    row.append(rng.randint(-100000, 100000) + row_index * 17 + column)
            random_rows.append(row)

        secret_offset = rng.randint(1000, 1000000)
        large_rows = []
        for i in range(60000):
            row = []
            for column in range(10):
                if (i * 7 + column * 11) % 23 == 0:
                    row.append(None)
                else:
                    row.append(((i + secret_offset) * (column + 3)) % 20001 - 10000)
            large_rows.append(row)

        for executable in ("/home/user/reducer", rebuilt):
            run_case(executable, random_rows)
            run_case(executable, large_rows, require_positive_benchmark=True)
    finally:
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass
        for path, content in saved.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                Path(path).write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
