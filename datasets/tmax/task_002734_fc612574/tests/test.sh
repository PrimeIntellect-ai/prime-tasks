#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess
import tempfile
import time

import h5py
import numpy as np


def read_partition_ids(path):
    with h5py.File(path, "r") as f:
        assert "/partition_ids" in f, "Output is missing /partition_ids"
        dataset = f["/partition_ids"]
        assert dataset.shape == (200000,), f"Unexpected partition_ids shape: {dataset.shape}"
        assert dataset.dtype == np.dtype("int32"), f"Unexpected partition_ids dtype: {dataset.dtype}"
        return dataset[:]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.digest()


def test_fast_partitioner_speedup_and_correctness():
    fast_bin = "/home/user/fast_partitioner"
    legacy_bin = "/app/legacy_partitioner"
    mesh_path = "/home/user/mesh_data.h5"
    out_path = "/home/user/optimized_partitions.h5"

    assert os.path.isfile(fast_bin), f"Agent executable not found at {fast_bin}"
    assert os.access(fast_bin, os.X_OK), f"Agent executable {fast_bin} is not executable"
    with open(fast_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_partitioner must be a compiled executable"
    assert sha256(fast_bin) != sha256(legacy_bin), "Submission is byte-identical to the legacy executable"

    num_points = 200000
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))

    # Keep the pristine input and both captured outputs in a root-only directory.
    # The agent runs before the oracle and cannot read this directory.
    with tempfile.TemporaryDirectory(prefix="partition_verify_", dir="/tmp") as private_dir:
        os.chmod(private_dir, 0o700)
        pristine_mesh = os.path.join(private_dir, "mesh.h5")
        saved_agent_out = os.path.join(private_dir, "agent.h5")
        legacy_out = os.path.join(private_dir, "legacy.h5")

        with h5py.File(pristine_mesh, "w") as f:
            f.create_dataset("/coordinates", data=rng.random((num_points, 3), dtype=np.float64))

        if os.path.lexists(mesh_path):
            os.remove(mesh_path)
        shutil.copy2(pristine_mesh, mesh_path)
        os.chmod(mesh_path, 0o644)
        if os.path.lexists(out_path):
            os.remove(out_path)

        # Run the submission first, as the unprivileged agent user. No oracle
        # output exists anywhere accessible to it during this execution.
        start_time = time.perf_counter()
        subprocess.run(
            ["runuser", "-u", "user", "--", fast_bin],
            check=True,
            timeout=30,
        )
        agent_time = time.perf_counter() - start_time

        assert os.path.isfile(out_path), f"Agent partitioner did not produce output at {out_path}"
        os.replace(out_path, saved_agent_out)
        agent_ids = read_partition_ids(saved_agent_out)

        # Restore the exact pristine input in case the submission attempted to
        # alter it, then run the oracle using only root-private paths.
        if os.path.lexists(mesh_path):
            os.remove(mesh_path)
        shutil.copy2(pristine_mesh, mesh_path)
        os.chmod(mesh_path, 0o644)

        start_time = time.perf_counter()
        subprocess.run(
            [legacy_bin, pristine_mesh, legacy_out],
            check=True,
            timeout=30,
        )
        legacy_time = time.perf_counter() - start_time

        assert os.path.isfile(legacy_out), "Legacy partitioner did not produce output"
        legacy_ids = read_partition_ids(legacy_out)

        np.testing.assert_array_equal(
            agent_ids,
            legacy_ids,
            err_msg="Agent's partition IDs do not match the legacy tool's output.",
        )

        speedup = legacy_time / agent_time
        assert speedup >= 3.0, (
            f"Speedup is {speedup:.2f}x (Legacy: {legacy_time:.3f}s, "
            f"Agent: {agent_time:.3f}s). Target is >= 3.0x."
        )

        # Preserve the required final output path after verification.
        shutil.copy2(saved_agent_out, out_path)


if __name__ == "__main__":
    test_fast_partitioner_speedup_and_correctness()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
