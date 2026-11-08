#!/bin/bash
mkdir -p /logs/verifier

WORKDIR=$(mktemp -d)
if [ -z "$WORKDIR" ] || [ ! -d "$WORKDIR" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
trap 'rm -rf "$WORKDIR"' EXIT

TRUSTED_LIB="$WORKDIR/libspecfact.so"
TRUSTED_ORACLE="$WORKDIR/reference_pipeline"

# Build a private reference library from the protected source so the oracle does
# not rely on an agent-built or agent-modified shared library.
if ! gcc -O2 -fPIC -shared /app/libspecfact-1.2.0/specfact.c -lm -o "$TRUSTED_LIB"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

if [ ! -f /tests/reference_pipeline ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

if ! sed "s|lib_path = \"/app/libspecfact-1.2.0/libspecfact.so\"|lib_path = \"$TRUSTED_LIB\"|" \
    /tests/reference_pipeline > "$TRUSTED_ORACLE"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
chmod 700 "$TRUSTED_ORACLE"
export REFERENCE_PIPELINE="$TRUSTED_ORACLE"

cat << 'TEST_EOF' > "$WORKDIR/test_final_state.py"
# test_final_state.py

import os
import stat
import subprocess
import tempfile
import numpy as np
import pytest

def test_shared_library_exists():
    lib_path = "/app/libspecfact-1.2.0/libspecfact.so"
    assert os.path.isfile(lib_path), f"Shared library {lib_path} was not built."

def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.py"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Pipeline script {script_path} is not executable."

def test_fuzz_equivalence():
    script_path = "/home/user/pipeline.py"
    oracle_path = os.environ["REFERENCE_PIPELINE"]

    assert os.path.isfile(oracle_path), f"Oracle {oracle_path} not found."

    np.random.seed(42)
    N = 50

    for i in range(N):
        # Generate random input
        input_data = np.random.uniform(0.0, 1.0, 65536).astype(np.float64)

        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as f_in:
            f_in.write(input_data.tobytes())
            input_file = f_in.name

        agent_out = input_file + "_agent.bin"
        oracle_out = input_file + "_oracle.bin"

        try:
            # Run oracle
            subprocess.run([oracle_path, input_file, oracle_out], check=True, capture_output=True)

            # Run agent
            subprocess.run([script_path, input_file, agent_out], check=True, capture_output=True)

            # Compare outputs
            assert os.path.isfile(agent_out), f"Agent did not produce output file {agent_out}"
            assert os.path.isfile(oracle_out), f"Oracle did not produce output file {oracle_out}"

            with open(agent_out, 'rb') as f:
                agent_bytes = f.read()
            with open(oracle_out, 'rb') as f:
                oracle_bytes = f.read()

            assert len(agent_bytes) == 1024, f"Expected agent output to be 1024 bytes, got {len(agent_bytes)}"
            assert agent_bytes == oracle_bytes, f"Fuzz mismatch on iteration {i}: agent output does not match oracle output."

        finally:
            for f in [input_file, agent_out, oracle_out]:
                if os.path.exists(f):
                    os.remove(f)

def test_visualization_generated():
    plot_path = "/home/user/visualization.png"
    assert os.path.isfile(plot_path), f"Visualization plot {plot_path} was not generated."
TEST_EOF

if python3 -m pytest "$WORKDIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
