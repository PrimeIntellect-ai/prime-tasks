#!/bin/bash
mkdir -p /logs/verifier

cat > /tmp/validate_gc.c <<'C_EOF'
#include <hdf5.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;

    hid_t file = H5Fopen(argv[1], H5F_ACC_RDONLY, H5P_DEFAULT);
    if (file < 0) return 3;
    hid_t ds = H5Dopen2(file, "/gc_distribution", H5P_DEFAULT);
    if (ds < 0) return 4;
    hid_t space = H5Dget_space(ds);
    if (space < 0 || H5Sget_simple_extent_ndims(space) != 1) return 5;

    hsize_t dims[1] = {0};
    if (H5Sget_simple_extent_dims(space, dims, NULL) < 0 || dims[0] != 10000) return 6;

    hid_t type = H5Dget_type(ds);
    if (type < 0 || H5Tget_class(type) != H5T_INTEGER || H5Tequal(type, H5T_NATIVE_INT) <= 0)
        return 7;

    int *actual = malloc(10000 * sizeof(*actual));
    if (!actual) return 8;
    if (H5Dread(ds, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, actual) < 0)
        return 9;

    srand48(42);
    long long total = 0;
    for (int trial = 0; trial < 10000; ++trial) {
        int expected = 0;
        for (int base = 0; base < 1000; ++base) {
            if (drand48() < 0.05) {
                long replacement = lrand48() % 3;
                if (replacement == 0 || replacement == 1) ++expected;
            }
        }
        if (actual[trial] != expected) {
            fprintf(stderr, "trial %d: expected %d, found %d\n", trial, expected, actual[trial]);
            return 10;
        }
        total += expected;
    }

    printf("%.10f\n", (double)total / 10000.0);
    free(actual);
    H5Tclose(type);
    H5Sclose(space);
    H5Dclose(ds);
    H5Fclose(file);
    return 0;
}
C_EOF

cat > /tmp/test_final_state.py <<'PY_EOF'
import os
import re
import subprocess
import pytest

H5_PATH = "/home/user/gc_data.h5"
SUMMARY_PATH = "/home/user/summary.txt"
SOURCE_PATH = "/home/user/sim.c"
EXE_PATH = "/home/user/sim"
VALIDATOR = "/tmp/validate_gc"


def run(cmd, timeout=90):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=True)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {cmd}")
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Command failed: {cmd}\nstdout:\n{exc.stdout}\nstderr:\n{exc.stderr}")
    except FileNotFoundError:
        pytest.fail(f"Command not found: {cmd[0]}")


def validate_data(path=H5_PATH):
    result = run([VALIDATOR, path])
    return float(result.stdout.strip())


def test_build_independent_validator():
    run(["h5cc", "/tmp/validate_gc.c", "-O2", "-o", VALIDATOR])
    assert os.path.isfile(VALIDATOR) and os.access(VALIDATOR, os.X_OK)


def test_h5_file_exists():
    assert os.path.isfile(H5_PATH), f"HDF5 file {H5_PATH} is missing."


def test_initial_dataset_values_and_summary():
    mean = validate_data()
    assert os.path.isfile(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing."
    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert re.fullmatch(r"Mean GC: [-+]?\d+\.\d{2}\n?", content), \
        f"Summary has the wrong format: {content!r}"
    assert content.strip() == f"Mean GC: {mean:.2f}", \
        "Summary mean was not calculated from the HDF5 values."


def test_source_and_executable_reproduce_distribution():
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} is missing."
    assert os.path.isfile(EXE_PATH), f"Simulator executable {EXE_PATH} is missing."
    assert os.access(EXE_PATH, os.X_OK), f"Simulator {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Simulator must be a compiled executable."

    with open(SOURCE_PATH, "r", encoding="utf-8", errors="strict") as f:
        source = f.read()
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    seed_calls = re.findall(r"\bsrand48\s*\(\s*42(?:[lL])?\s*\)", code)
    assert len(seed_calls) == 1, "sim.c must call srand48(42) exactly once."
    assert re.search(r"\bdrand48\s*\(", code), "sim.c must use drand48()."
    assert re.search(r"\blrand48\s*\(", code), "sim.c must use lrand48()."

    rebuilt = "/tmp/submission_sim"
    run(["h5cc", SOURCE_PATH, "-O2", "-o", rebuilt])

    for executable in (rebuilt, EXE_PATH):
        if os.path.exists(H5_PATH):
            os.remove(H5_PATH)
        run([executable])
        assert os.path.isfile(H5_PATH), f"{executable} did not create {H5_PATH}."
        validate_data()


def test_h5_dataset_metadata():
    assert os.path.isfile(H5_PATH), f"HDF5 file {H5_PATH} is missing."
    try:
        result = subprocess.run(
            ["h5dump", "-H", H5_PATH],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"h5dump failed on {H5_PATH}: {e.stderr}")
    except FileNotFoundError:
        pytest.fail("h5dump command not found. Ensure hdf5-tools is installed.")

    output = result.stdout
    assert 'DATASET "gc_distribution"' in output or 'DATASET "/gc_distribution"' in output, \
        "Dataset 'gc_distribution' not found in the HDF5 file."
    assert "DATASPACE  SIMPLE { ( 10000 ) / ( 10000 ) }" in output or \
           "DATASPACE  SIMPLE { ( 10000 ) / ( H5S_UNLIMITED ) }" in output or \
           "10000" in output, "Dataset dimensions must be exactly 10000."


def test_summary_file_exists_and_content():
    assert os.path.isfile(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing."
    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content.startswith("Mean GC:"), \
        f"Summary file does not start with 'Mean GC:'. Found: {content}"
    try:
        val_str = content.split("Mean GC:")[1].strip()
        val = float(val_str)
        assert 33.00 <= val <= 34.00, \
            f"Calculated mean {val} is outside the expected range (33.00 - 34.00)."
    except ValueError:
        pytest.fail(f"Could not parse the mean value from summary file content: {content}")

    expected_mean = validate_data()
    assert content == f"Mean GC: {expected_mean:.2f}", \
        "Summary does not exactly match the verified distribution mean rounded to two decimals."
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
