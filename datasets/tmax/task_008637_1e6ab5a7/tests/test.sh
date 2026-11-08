#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

WORKSPACE = Path("/home/user/workspace")

ORIGINAL_FILES = {
    "matrix_ops.h": "#ifndef MATRIX_OPS_H\n#define MATRIX_OPS_H\n\nvoid mat_mult(double* A, double* B, double* C, int m, int n, int p);\n\n#endif\n",
    "matrix_ops.c": "#include \"matrix_ops.h\"\n#include <stdio.h>\n\nvoid mat_mult(double* A, double* B, double* C, int m, int n, int p) {\n#ifdef USE_FAST_MATH\n    for(int i=0; i<m; i++) {\n        for(int j=0; j<p; j++) {\n            C[i*p + j] = 0;\n            for(int k=0; k<n; k++) {\n                C[i*p + j] += A[i*n + k] * B[k*p + j];\n            }\n        }\n    }\n#else\n    // Fallback stub: silent failure\n    for(int i=0; i<m*p; i++) {\n        C[i] = 0.0;\n    }\n#endif\n}\n",
    "process.c": "#include <stdio.h>\n#include <stdlib.h>\n#include \"matrix_ops.h\"\n\nvoid load_csv(const char* filename, double* matrix, int rows, int cols) {\n    FILE* f = fopen(filename, \"r\");\n    if(!f) return;\n    for(int i=0; i<rows; i++) {\n        for(int j=0; j<cols; j++) {\n            if(j == cols - 1) fscanf(f, \"%lf\", &matrix[i*cols + j]);\n            else fscanf(f, \"%lf,\", &matrix[i*cols + j]);\n        }\n    }\n    fclose(f);\n}\n\nint main() {\n    int m = 5; // rows in data\n    int n = 3; // cols in data, rows in proj\n    int p = 2; // cols in proj\n\n    double* data = (double*)malloc(m * n * sizeof(double));\n    double* proj = (double*)malloc(n * p * sizeof(double));\n    double* out  = (double*)malloc(m * p * sizeof(double));\n\n    load_csv(\"data.csv\", data, m, n);\n    load_csv(\"proj.csv\", proj, n, p);\n\n    mat_mult(data, proj, out, m, n, p);\n\n    FILE* f = fopen(\"output.csv\", \"w\");\n    for(int i=0; i<m; i++) {\n        fprintf(f, \"%f,%f\\n\", out[i*p], out[i*p + 1]);\n    }\n    fclose(f);\n\n    free(data);\n    free(proj);\n    free(out);\n    return 0;\n}\n",
    "data.csv": "1.0,2.0,3.0\n2.0,3.0,4.0\n3.0,4.0,5.0\n4.0,5.0,6.0\n5.0,6.0,7.0\n",
    "proj.csv": "0.5,0.1\n0.3,0.2\n0.2,0.7\n",
}


def assert_original_inputs():
    for name, expected in ORIGINAL_FILES.items():
        path = WORKSPACE / name
        assert path.is_file(), f"Required file {path} is missing."
        assert path.read_text() == expected, f"{name} was modified, but only the Makefile may be changed."


def write_csv(path, rows):
    path.write_text("".join(",".join(format(value, ".17g") for value in row) + "\n" for row in rows))


def read_output(path):
    assert path.is_file(), f"File {path} is missing."
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    assert len(lines) == 5, f"Expected output.csv to have 5 rows, but found {len(lines)}."
    result = []
    for i, line in enumerate(lines):
        parts = line.split(",")
        assert len(parts) == 2, f"Expected 2 columns in output.csv at row {i+1}, found {len(parts)}."
        values = [float(part) for part in parts]
        assert all(math.isfinite(value) for value in values), f"Row {i+1} contains a non-finite value."
        result.append(values)
    return result


def multiply(data, projection):
    return [
        [sum(row[k] * projection[k][j] for k in range(3)) for j in range(2)]
        for row in data
    ]


def assert_matrix_close(actual, expected):
    assert len(actual) == len(expected)
    for i, (actual_row, expected_row) in enumerate(zip(actual, expected)):
        for j, (actual_value, expected_value) in enumerate(zip(actual_row, expected_row)):
            assert actual_value == pytest.approx(expected_value, abs=1e-6), (
                f"Incorrect matrix product at row {i+1}, column {j+1}: "
                f"expected {expected_value}, found {actual_value}"
            )


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_execute_pipeline():
    assert_original_inputs()

    subprocess.run(["make", "clean"], cwd=WORKSPACE, check=True, timeout=20)
    for name in ("process", "output.csv"):
        path = WORKSPACE / name
        if path.exists() or path.is_symlink():
            path.unlink()

    subprocess.run(["make", "all"], cwd=WORKSPACE, check=True, timeout=20)

    executable = WORKSPACE / "process"
    assert executable.is_file(), "The build did not create the process executable."
    assert os.access(executable, os.X_OK), "The generated process file is not executable."
    assert executable.read_bytes()[:4] == b"\x7fELF", "The build output is not a compiled ELF executable."

    rng = random.Random(928374)
    for _ in range(3):
        data = [[rng.uniform(-8.0, 8.0) for _ in range(3)] for _ in range(5)]
        projection = [[rng.uniform(-4.0, 4.0) for _ in range(2)] for _ in range(3)]
        expected = multiply(data, projection)

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            shutil.copy2(executable, temp / "process")
            write_csv(temp / "data.csv", data)
            write_csv(temp / "proj.csv", projection)
            subprocess.run([str(temp / "process")], cwd=temp, check=True, timeout=10)
            assert_matrix_close(read_output(temp / "output.csv"), expected)

    subprocess.run([str(executable)], cwd=WORKSPACE, check=True, timeout=10)
    assert_original_inputs()
    yield


def test_source_files_remained_unmodified():
    assert_original_inputs()


def test_summary_txt_exists_and_correct():
    summary_path = WORKSPACE / "summary.txt"
    assert summary_path.is_file(), f"File {summary_path} is missing."

    raw_content = summary_path.read_text()
    content = raw_content.strip()

    assert content == "3.7", f"Expected summary.txt to contain exactly '3.7', but found '{content}'"
    assert raw_content == "3.7", "summary.txt must contain nothing but the one-decimal numeric value."


def test_output_csv_correct():
    output_path = WORKSPACE / "output.csv"
    actual = read_output(output_path)

    data = [[float(value) for value in line.split(",")] for line in ORIGINAL_FILES["data.csv"].strip().splitlines()]
    projection = [[float(value) for value in line.split(",")] for line in ORIGINAL_FILES["proj.csv"].strip().splitlines()]
    expected = multiply(data, projection)
    assert_matrix_close(actual, expected)

    first_col_sum = 0.0
    for i, (val1, val2) in enumerate(actual):
        assert val1 != 0.0 or val2 != 0.0, f"Row {i+1} still contains zeros. The pipeline might not have been recompiled or run correctly."
        first_col_sum += val1

    avg = first_col_sum / len(actual)
    assert round(avg, 1) == 3.7, f"Expected the average of the first column to be 3.7, but calculated {avg:.2f}."
    assert (WORKSPACE / "summary.txt").read_text() == f"{avg:.1f}"


def test_makefile_fixed():
    makefile_path = WORKSPACE / "Makefile"
    assert makefile_path.is_file(), f"File {makefile_path} is missing."

    content = makefile_path.read_text()
    assert "USE_FAST_MATH" in content, "The Makefile does not appear to have been modified to include the USE_FAST_MATH macro."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
