#!/bin/bash
mkdir -p /logs/verifier

cat << 'SRC_EOF' > /tmp/reference_matrix_sim.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

void cholesky(double A[3][3], double L[3][3]) {
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j <= i; j++) {
            double sum = 0;
            for (int k = 0; k < j; k++) {
                sum += L[i][k] * L[j][k];
            }
            if (i == j) {
                double val = A[i][i] - sum;
                if (val <= 0.0) {
                    printf("DIVERGED\n");
                    exit(0);
                }
                L[i][j] = sqrt(val);
            } else {
                L[i][j] = (1.0 / L[j][j] * (A[i][j] - sum));
            }
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double dt = atof(argv[1]);
    double A[3][3] = {
        {4.0, 1.0, 1.0},
        {1.0, 5.0, 2.0},
        {1.0, 2.0, 6.0}
    };
    for (int step = 0; step < 100; step++) {
        A[0][0] -= dt * 0.52;
        A[1][1] -= dt * 0.2;
        A[2][2] -= dt * 0.1;
        double L[3][3] = {0};
        cholesky(A, L);
    }
    printf("SUCCESS\n");
    return 0;
}
SRC_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile

EXE = "/home/user/matrix_sim"
SCRIPT = "/home/user/profile.sh"
REFERENCE = "/tmp/reference_matrix_sim"
DTS = [f"{i / 1000:.3f}" for i in range(10, 101)]


def run_program(path, *args):
    return subprocess.run(
        [path, *args], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )


def expected_rows():
    rows = []
    for dt in DTS:
        proc = run_program(REFERENCE, dt)
        assert proc.returncode == 0
        status = proc.stdout.strip()
        assert status in {"SUCCESS", "DIVERGED"}
        rows.append(f"{dt},{status}")
    return rows


def test_executable_compiled():
    """Test that matrix_sim was compiled and is executable."""
    assert os.path.isfile(EXE), f"The compiled executable {EXE} is missing."
    assert os.access(EXE, os.X_OK), f"The file {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "matrix_sim must be a compiled ELF executable."


def test_profile_script_exists_and_executable():
    """Test that profile.sh exists and is executable."""
    assert os.path.isfile(SCRIPT), f"The bash script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable."


def test_executable_matches_supplied_source():
    with tempfile.TemporaryDirectory() as td:
        submitted = os.path.join(td, "submitted")
        reference = os.path.join(td, "reference")
        shutil.copy2(EXE, submitted)
        shutil.copy2(REFERENCE, reference)
        subprocess.run(["strip", "--strip-all", submitted], check=True)
        subprocess.run(["strip", "--strip-all", reference], check=True)
        with open(submitted, "rb") as f:
            submitted_bytes = f.read()
        with open(reference, "rb") as f:
            reference_bytes = f.read()
        assert submitted_bytes == reference_bytes, (
            "matrix_sim is not the gcc -O2/-lm build of the supplied source."
        )

    for dt in DTS:
        actual = run_program(EXE, dt)
        expected = run_program(REFERENCE, dt)
        assert (actual.returncode, actual.stdout) == (expected.returncode, expected.stdout), (
            f"matrix_sim produced the wrong result for dt={dt}."
        )

    actual = run_program(EXE)
    expected = run_program(REFERENCE)
    assert actual.returncode == expected.returncode


def test_profile_script_runs_full_sweep():
    for path in ("/home/user/results.csv", "/home/user/optimal_dt.txt"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    backup = "/home/user/.matrix_sim.verifier_backup"
    log = "/tmp/matrix_sim_calls.log"
    try:
        os.remove(log)
    except FileNotFoundError:
        pass
    shutil.copy2(EXE, backup)

    wrapper = f'''#!/bin/bash
printf '%s:%s\\n' "$#" "$1" >> {log}
exec {backup} "$@"
'''
    try:
        with open(EXE, "w") as f:
            f.write(wrapper)
        os.chmod(EXE, 0o755)
        proc = subprocess.run(
            [SCRIPT], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        assert proc.returncode == 0, f"profile.sh failed: {proc.stderr}"
    finally:
        os.replace(backup, EXE)

    assert os.path.isfile(log), "profile.sh did not invoke ./matrix_sim."
    with open(log) as f:
        calls = [line.rstrip("\n") for line in f]
    assert calls == [f"1:{dt}" for dt in DTS], (
        "profile.sh must invoke matrix_sim exactly once for every dt from 0.010 through 0.100."
    )


def test_results_csv_content():
    """Test that results.csv has the correct format and data."""
    csv_path = "/home/user/results.csv"
    assert os.path.isfile(csv_path), f"The results file {csv_path} is missing."

    with open(csv_path, "r") as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]

    assert len(lines) == 91, f"Expected 91 lines in {csv_path}, found {len(lines)}."
    assert raw_lines == expected_rows(), "results.csv does not contain the complete ordered simulation sweep."

    assert lines[0] == "0.010,SUCCESS", f"Expected first line to be '0.010,SUCCESS', found '{lines[0]}'."
    assert lines[66] == "0.076,SUCCESS", f"Expected line for dt=0.076 to be '0.076,SUCCESS', found '{lines[66]}'."
    assert lines[67] == "0.077,DIVERGED", f"Expected line for dt=0.077 to be '0.077,DIVERGED', found '{lines[67]}'."
    assert lines[-1] == "0.100,DIVERGED", f"Expected last line to be '0.100,DIVERGED', found '{lines[-1]}'."


def test_optimal_dt_content():
    """Test that optimal_dt.txt contains the correct value."""
    txt_path = "/home/user/optimal_dt.txt"
    assert os.path.isfile(txt_path), f"The file {txt_path} is missing."

    with open(txt_path, "r") as f:
        content = f.read().strip()

    assert content == "0.076", f"Expected optimal_dt.txt to contain '0.076', found '{content}'."
    successes = [row.split(",", 1)[0] for row in expected_rows() if row.endswith(",SUCCESS")]
    assert content == max(successes), "optimal_dt.txt is not the maximum successful dt."
TEST_EOF

compile_ok=1
gcc -O2 /tmp/reference_matrix_sim.c -lm -o /tmp/reference_matrix_sim || compile_ok=0

if [ "$compile_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
