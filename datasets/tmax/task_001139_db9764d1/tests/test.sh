#!/bin/bash
set -u
mkdir -p /logs/verifier

# The oracle remains available to the root verifier, but agent code is exercised as
# the unprivileged user and cannot invoke it directly during verification.
chmod 700 /app/bio_sim 2>/dev/null || true
pkill -KILL -u user 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import subprocess
import tempfile
import pytest

ORACLE = "/app/bio_sim"
AGENT_SCRIPT = "/home/user/emulator.py"
USER = pwd.getpwnam("user")


def demote():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_agent(args, timeout=15):
    return subprocess.run(
        ["/usr/bin/python3", AGENT_SCRIPT] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
        preexec_fn=demote,
    )


def simulate(p0, r, k, tmax):
    P = float(p0)
    r = float(r)
    K = float(k)
    T_max = float(tmax)
    t = 0.0
    dt = 0.1

    while t < T_max:
        dP = r * P * (1.0 - P / K)
        if dP > 10.0:
            dt = 0.05
        elif dP < 1.0:
            dt = 0.2
        else:
            dt = 0.1

        if t + dt > T_max:
            dt = T_max - t

        P = P + dP * dt
        t = t + dt

        if P < 0.0 or P > 1000000.0:
            P = -1.0
            break

    return P


def expected_text(args):
    return format(simulate(*args), ".5f")


def test_emulator_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle missing: {ORACLE}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"

    random.seed(42)
    for _ in range(1000):
        p0 = random.uniform(0.1, 100.0)
        r = random.uniform(0.01, 5.0)
        k = random.uniform(50.0, 500.0)
        tmax = random.uniform(1.0, 20.0)
        args = [str(p0), str(r), str(k), str(tmax)]

        oracle_proc = subprocess.run([ORACLE] + args, capture_output=True, text=True)
        agent_proc = run_agent(args)

        assert oracle_proc.returncode == 0, f"Oracle failed on inputs {args}"
        assert agent_proc.returncode == 0, (
            f"Agent script failed on inputs {args}\nStderr: {agent_proc.stderr}"
        )

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()
        assert oracle_out == agent_out, (
            f"Output mismatch on inputs {args}.\n"
            f"Oracle output: {oracle_out}\nAgent output:  {agent_out}"
        )
        assert agent_out == expected_text(args), (
            f"Output differs from independently derived simulation on {args}: "
            f"expected {expected_text(args)}, got {agent_out}"
        )


def test_emulator_does_not_forward_to_an_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    rng = random.SystemRandom()

    for _ in range(32):
        args = [
            str(rng.uniform(0.1, 100.0)),
            str(rng.uniform(0.01, 5.0)),
            str(rng.uniform(50.0, 500.0)),
            str(rng.uniform(1.0, 20.0)),
        ]
        fd, trace_path = tempfile.mkstemp(prefix="emulator-trace-", dir="/tmp")
        os.close(fd)
        os.unlink(trace_path)
        try:
            proc = subprocess.run(
                ["/usr/bin/strace", "-f", "-qq", "-e", "trace=process",
                 "-o", trace_path, "/usr/bin/python3", AGENT_SCRIPT] + args,
                capture_output=True,
                text=True,
                timeout=15,
                preexec_fn=demote,
            )
            assert proc.returncode == 0, (
                f"Traced emulator failed on {args}\nStderr: {proc.stderr}"
            )
            assert proc.stdout.strip() == expected_text(args)

            with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
                trace = f.read()

            # One execve is the initial launch of Python by strace. Any further
            # process creation or execution means the emulator delegated its work.
            assert trace.count("execve(") == 1, (
                f"Emulator executed another program on inputs {args}\n{trace}"
            )
            assert not re.search(r"(?:^|\s)(?:fork|vfork|clone|clone3)\(", trace, re.M), (
                f"Emulator created a subprocess on inputs {args}\n{trace}"
            )
        finally:
            try:
                os.unlink(trace_path)
            except FileNotFoundError:
                pass


def test_processed_data():
    processed_file = "/home/user/processed_data.h5"
    assert os.path.exists(processed_file), f"Processed data file missing: {processed_file}"

    check_script = r'''
import sys
import h5py
import netCDF4 as nc
import subprocess

try:
    ds = nc.Dataset('/home/user/raw_inputs.nc', 'r')
    P0 = ds.variables['P0'][:]
    r = ds.variables['r'][:]
    K = ds.variables['K'][:]
    Tmax = ds.variables['Tmax'][:]
    ds.close()

    with h5py.File('/home/user/processed_data.h5', 'r') as f:
        if 'final_states' not in f:
            print("Dataset 'final_states' not found in HDF5 file")
            sys.exit(1)
        final_states = f['final_states'][:]

    if len(final_states) != 50:
        print(f"Expected 50 final states, got {len(final_states)}")
        sys.exit(1)

    for i in range(50):
        args = [str(P0[i]), str(r[i]), str(K[i]), str(Tmax[i])]
        oracle_proc = subprocess.run(['/app/bio_sim'] + args, capture_output=True, text=True)
        if oracle_proc.returncode != 0:
            print(f"Oracle failed at index {i}")
            sys.exit(1)
        expected_val = float(oracle_proc.stdout.strip())
        actual_val = float(final_states[i])
        if abs(expected_val - actual_val) > 1e-4:
            print(f"Mismatch at index {i} for inputs {args}: expected {expected_val}, got {actual_val}")
            sys.exit(1)

    print('OK')
except Exception as e:
    print(f"Error during validation: {str(e)}")
    sys.exit(1)
'''
    result = subprocess.run(["python3", "-c", check_script], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Processed data validation failed:\n{result.stdout}\n{result.stderr}"
    )
    assert result.stdout.strip() == "OK", (
        f"Processed data validation did not output OK:\n{result.stdout}"
    )

    import h5py
    import netCDF4 as nc

    ds = nc.Dataset('/home/user/raw_inputs.nc', 'r')
    P0 = ds.variables['P0'][:]
    r = ds.variables['r'][:]
    K = ds.variables['K'][:]
    Tmax = ds.variables['Tmax'][:]
    ds.close()

    with h5py.File(processed_file, 'r') as f:
        final_states = f['final_states'][:]

    for i in range(50):
        args = [str(P0[i]), str(r[i]), str(K[i]), str(Tmax[i])]
        expected = float(expected_text(args))
        actual = float(final_states[i])
        assert abs(expected - actual) <= 1e-4, (
            f"Independent processed-data mismatch at index {i}: "
            f"expected {expected}, got {actual}"
        )

        emulator_proc = run_agent(args)
        assert emulator_proc.returncode == 0, (
            f"Emulator failed for dataset row {i}: {emulator_proc.stderr}"
        )
        assert abs(float(emulator_proc.stdout.strip()) - actual) <= 1e-4, (
            f"Dataset row {i} does not match emulator output"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
