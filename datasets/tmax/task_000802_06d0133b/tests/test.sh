#!/bin/bash
set +e
mkdir -p /logs/verifier

verify() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_integrate_c_fixed():
    path = "/home/user/sim/integrate.c"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "dt * 2.0" not in content, "The bug 'dt * 2.0' is still present in integrate.c."
    assert "0.5" in content, "The multiplier was not changed to 0.5 (or similar logic) in integrate.c."
    assert "MPI_Allreduce" in content, "MPI_Allreduce is missing from integrate.c."
    assert "MPI_MIN" in content, "MPI_MIN is missing from the MPI_Allreduce call in integrate.c."


def test_executable_exists():
    path = "/home/user/sim/integrate"
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_hdf5_output_exists():
    path = "/home/user/sim/output.h5"
    assert os.path.isfile(path), f"HDF5 output file {path} is missing. Did you run the simulation?"


def test_result_txt_exists_and_correct():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"Result file {path} is missing. Did you run h5dump?"
    with open(path, "r") as f:
        content = f.read()
    assert "HDF5" in content, f"{path} does not appear to contain h5dump output."
    assert "DATA {" in content, f"{path} does not contain dataset data."
    expected_values = [1.5, 2.5, 3.5, 4.5]
    for val in expected_values:
        assert str(val) in content, f"Expected value {val} not found in {path}. The simulation logic or MPI execution might be incorrect."
    data_section = re.search(r'DATA\s*\{\s*(.*?)\s*\}', content, re.DOTALL)
    if data_section:
        numbers = re.findall(r'\d+\.\d+', data_section.group(1))
        if numbers:
            assert len(numbers) >= 4, f"Expected at least 4 values in the dataset, found {len(numbers)}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
    readelf -h /home/user/sim/integrate >/dev/null 2>&1 || return 1

    # Build a profiling shim that verifies the program really performs one
    # double-precision MPI_MIN reduction on MPI_COMM_WORLD per time step. The
    # shim returns a synchronized 0.1 test step so the supplied mock error model
    # (which otherwise keeps halving forever after t > 0.5) can be exercised to
    # completion without changing the submitted source.
    cat << 'EOF' > /tmp/mpi_probe.c
#include <mpi.h>
#include <stdio.h>

int MPI_Allreduce(const void *sendbuf, void *recvbuf, int count,
                  MPI_Datatype datatype, MPI_Op op, MPI_Comm comm) {
    int rank = -1;
    PMPI_Comm_rank(MPI_COMM_WORLD, &rank);
    int cmp = MPI_UNEQUAL;
    PMPI_Comm_compare(comm, MPI_COMM_WORLD, &cmp);
    int valid = (count == 1 && datatype == MPI_DOUBLE && op == MPI_MIN && cmp == MPI_IDENT);
    double input = 0.0;
    if (valid)
        input = (sendbuf == MPI_IN_PLACE) ? *(double *)recvbuf : *(const double *)sendbuf;

    int rc = PMPI_Allreduce(sendbuf, recvbuf, count, datatype, op, comm);
    if (valid && rc == MPI_SUCCESS) {
        /* Force a finite, globally synchronized test trajectory. */
        *(double *)recvbuf = 0.1;
        char path[128];
        snprintf(path, sizeof(path), "/tmp/mpi_probe_%d.log", rank);
        FILE *f = fopen(path, "a");
        if (f) {
            fprintf(f, "%.17g %.17g\n", input, *(double *)recvbuf);
            fclose(f);
        }
    }
    return rc;
}
EOF
    mpicc -shared -fPIC /tmp/mpi_probe.c -o /tmp/mpi_probe.so || return 1

    # Independently compile the submitted source, ensuring the tested behavior
    # comes from integrate.c rather than from an unrelated executable.
    h5pcc /home/user/sim/integrate.c -o /tmp/integrate_from_source || return 1

    run_and_check() {
        local executable="$1"
        rm -f /tmp/mpi_probe_*.log /home/user/sim/output.h5
        OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
            LD_PRELOAD=/tmp/mpi_probe.so \
            timeout 30s mpirun -np 4 "$executable" >/tmp/integrate.stdout 2>/tmp/integrate.stderr || return 1

        python3 - << 'PY'
import math
import os

# Derive the expected inputs to MPI_Allreduce from the requested adaptive
# stepping algorithm. The probe returns dt=0.1 after every valid reduction.
dt = 0.1
t = 0.0
expected = []
while t < 1.0:
    error = 0.02 if t > 0.5 else 0.001
    dt = dt * (0.5 if error > 0.01 else 1.1)
    expected.append(dt)
    dt = 0.1
    if t + dt > 1.0:
        dt = 1.0 - t
    t += dt
    if len(expected) > 20:
        raise AssertionError("unexpected expected-trajectory length")

assert len(expected) == 11
for rank in range(4):
    path = f"/tmp/mpi_probe_{rank}.log"
    assert os.path.isfile(path), f"rank {rank} made no valid MPI_Allreduce calls"
    with open(path) as f:
        rows = [tuple(map(float, line.split())) for line in f if line.strip()]
    assert len(rows) >= len(expected), f"rank {rank} made too few valid reductions"
    for i, wanted in enumerate(expected):
        actual, reduced = rows[i]
        assert math.isclose(actual, wanted, rel_tol=1e-12, abs_tol=1e-14), \
            f"rank {rank}, step {i}: reduction input {actual}, expected {wanted}"
        assert math.isclose(reduced, 0.1, rel_tol=0.0, abs_tol=1e-15)
PY
    }

    # Exercise both the demanded executable and a clean build of the submitted source.
    run_and_check /home/user/sim/integrate || return 1
    run_and_check /tmp/integrate_from_source || return 1

    # Parse the actual HDF5 object through the HDF5 API; do not trust result.txt.
    cat << 'EOF' > /tmp/check_h5.c
#include <mpi.h>
#include <hdf5.h>
#include <math.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int ok = 1;
    hid_t file = H5Fopen("/home/user/sim/output.h5", H5F_ACC_RDONLY, H5P_DEFAULT);
    if (file < 0) ok = 0;
    hid_t dset = ok ? H5Dopen2(file, "result", H5P_DEFAULT) : -1;
    if (dset < 0) ok = 0;
    hid_t space = ok ? H5Dget_space(dset) : -1;
    hsize_t dims[1] = {0};
    if (space < 0 || H5Sget_simple_extent_ndims(space) != 1 ||
        H5Sget_simple_extent_dims(space, dims, NULL) < 0 || dims[0] != 4) ok = 0;
    hid_t type = ok ? H5Dget_type(dset) : -1;
    if (type < 0 || H5Tget_class(type) != H5T_FLOAT || H5Tget_size(type) != 8) ok = 0;
    double values[4] = {0,0,0,0};
    if (ok && H5Dread(dset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, values) < 0) ok = 0;
    for (int i = 0; ok && i < 4; ++i)
        if (!isfinite(values[i]) || fabs(values[i] - (1.5 + i)) > 1e-12) ok = 0;
    if (type >= 0) H5Tclose(type);
    if (space >= 0) H5Sclose(space);
    if (dset >= 0) H5Dclose(dset);
    if (file >= 0) H5Fclose(file);
    MPI_Finalize();
    return ok ? 0 : 1;
}
EOF
    h5pcc /tmp/check_h5.c -o /tmp/check_h5 || return 1
    /tmp/check_h5 || return 1

    # result.txt must be the actual standard output of h5dump for this file.
    h5dump /home/user/sim/output.h5 > /tmp/actual_h5dump.txt || return 1
    cmp -s /home/user/result.txt /tmp/actual_h5dump.txt || return 1
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
