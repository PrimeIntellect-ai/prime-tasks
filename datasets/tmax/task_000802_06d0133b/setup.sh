#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for the task
    apt-get install -y openmpi-bin libopenmpi-dev libhdf5-openmpi-dev hdf5-tools gcc

    # Create directories and files
    mkdir -p /home/user/sim
    cat << 'EOF' > /home/user/sim/integrate.c
#include <mpi.h>
#include <hdf5.h>
#include <stdio.h>
#include <math.h>

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    double dt = 0.1;
    double t = 0;
    double t_end = 1.0;
    double val = 1.0 + rank;

    while (t < t_end) {
        // Mock error evaluation
        double error = t > 0.5 ? 0.02 : 0.001;
        double tolerance = 0.01;

        // Step size adaptation
        if (error > tolerance) {
            dt = dt * 2.0; // BUG: Should decrease dt
        } else {
            dt = dt * 1.1; // Increase dt if error is small
        }

        // MISSING: MPI_Allreduce to find global minimum dt

        if (t + dt > t_end) dt = t_end - t;

        val += dt * 0.5; // Mock integration step
        t += dt;
    }

    // Write to HDF5 using parallel I/O
    hid_t plist_id = H5Pcreate(H5P_FILE_ACCESS);
    H5Pset_fapl_mpio(plist_id, MPI_COMM_WORLD, MPI_INFO_NULL);
    hid_t file_id = H5Fcreate("/home/user/sim/output.h5", H5F_ACC_TRUNC, H5P_DEFAULT, plist_id);
    H5Pclose(plist_id);

    hsize_t dims[1] = {size};
    hid_t filespace = H5Screate_simple(1, dims, NULL);
    hid_t dataset_id = H5Dcreate(file_id, "result", H5T_NATIVE_DOUBLE, filespace, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);

    hsize_t dimsm[1] = {1};
    hid_t memspace = H5Screate_simple(1, dimsm, NULL);
    hsize_t offset = rank;
    hsize_t count = 1;
    H5Sselect_hyperslab(filespace, H5S_SELECT_SET, &offset, NULL, &count, NULL);

    plist_id = H5Pcreate(H5P_DATASET_XFER);
    H5Pset_dxpl_mpio(plist_id, H5FD_MPIO_COLLECTIVE);

    H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, memspace, filespace, plist_id, &val);

    H5Dclose(dataset_id);
    H5Sclose(filespace);
    H5Sclose(memspace);
    H5Pclose(plist_id);
    H5Fclose(file_id);

    MPI_Finalize();
    return 0;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
