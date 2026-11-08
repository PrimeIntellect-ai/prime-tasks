#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import random
import stat
import subprocess
import tempfile

import pytest


def test_cipher_fuzz_equivalence():
    oracle_path = "/app/bin/cipher_oracle"
    agent_path = "/home/user/cipher"

    assert os.path.exists(agent_path), f"Agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable"

    random.seed(42)
    N = 500
    for i in range(N):
        length = random.randint(0, 65536)
        input_data = random.randbytes(length)

        oracle_proc = subprocess.run([oracle_path], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, capture_output=True)

        assert agent_proc.returncode == oracle_proc.returncode, f"Return code mismatch on input length {length}"
        if agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(f"Output mismatch on input length {length}. Agent output did not match oracle output.")


@contextlib.contextmanager
def patched_commands(df_wrapper, ip_wrapper):
    replacements = {}
    candidates = {
        "/bin/df": df_wrapper,
        "/usr/bin/df": df_wrapper,
        "/bin/ip": ip_wrapper,
        "/usr/bin/ip": ip_wrapper,
        "/sbin/ip": ip_wrapper,
        "/usr/sbin/ip": ip_wrapper,
    }
    try:
        for candidate, wrapper in candidates.items():
            if not os.path.exists(candidate):
                continue
            real_path = os.path.realpath(candidate)
            if real_path in replacements:
                continue
            with open(real_path, "rb") as f:
                original = f.read()
            mode = stat.S_IMODE(os.stat(real_path).st_mode)
            replacements[real_path] = (original, mode)
            with open(wrapper, "rb") as src, open(real_path, "wb") as dst:
                dst.write(src.read())
            os.chmod(real_path, 0o755)
        yield
    finally:
        for real_path, (original, mode) in replacements.items():
            with open(real_path, "wb") as f:
                f.write(original)
            os.chmod(real_path, mode)


def test_setup_restore_behavior():
    script = "/home/user/setup_restore.sh"
    route_path = "/home/user/route_command.txt"
    restored_path = "/home/user/restored.tar"
    assert os.path.exists(script), f"File {script} not found."
    assert os.access(script, os.X_OK), f"File {script} is not executable."

    with tempfile.TemporaryDirectory() as td:
        fakebin = os.path.join(td, "bin")
        os.mkdir(fakebin)
        df_log = os.path.join(td, "df.log")
        ip_log = os.path.join(td, "ip.log")
        df_wrapper = os.path.join(fakebin, "df")
        ip_wrapper = os.path.join(fakebin, "ip")

        with open(df_wrapper, "w") as f:
            f.write("#!/bin/sh\n"
                    "printf '%s\\n' \"$*\" >> \"$MOCK_DF_LOG\"\n"
                    "printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\\n'\n"
                    "printf '/dev/mock 9999999 1 %s 1%% /home/user\\n' \"$MOCK_DF_AVAILABLE\"\n")
        with open(ip_wrapper, "w") as f:
            f.write("#!/bin/sh\n"
                    "printf '%s\\n' \"$*\" >> \"$MOCK_IP_LOG\"\n"
                    "printf 'default via 198.51.100.1 dev %s proto static\\n' \"$MOCK_IFACE\"\n")
        os.chmod(df_wrapper, 0o755)
        os.chmod(ip_wrapper, 0o755)

        env = os.environ.copy()
        env["PATH"] = fakebin + os.pathsep + env.get("PATH", "")
        env["MOCK_DF_LOG"] = df_log
        env["MOCK_IP_LOG"] = ip_log
        env["MOCK_DF_AVAILABLE"] = "1048576"
        env["MOCK_IFACE"] = "verifyif37"

        for path in (route_path, restored_path):
            if os.path.exists(path):
                os.remove(path)

        with patched_commands(df_wrapper, ip_wrapper):
            no_arg = subprocess.run([script], env=env, capture_output=True, timeout=20)
            assert no_arg.returncode != 0, "setup_restore.sh must reject zero arguments"
            assert not os.path.exists(route_path), "The script performed routing work after rejecting zero arguments"
            assert not os.path.exists(restored_path), "The script performed restore work after rejecting zero arguments"

            two_args = subprocess.run(
                [script, "192.168.50.20", "extra"], env=env,
                capture_output=True, timeout=20
            )
            assert two_args.returncode != 0, "setup_restore.sh must reject more than one argument"
            assert not os.path.exists(route_path), "The script performed routing work after rejecting extra arguments"
            assert not os.path.exists(restored_path), "The script performed restore work after rejecting extra arguments"

            boundary = subprocess.run(
                [script, "192.168.50.20"], env=env,
                capture_output=True, timeout=30
            )
            assert boundary.returncode == 0, boundary.stderr.decode(errors="replace")
            assert not os.path.exists(restored_path), "Exactly 1048576 KB is not more than the required free-space threshold"
            assert os.path.exists(route_path), "The script did not create route_command.txt"
            with open(route_path) as f:
                boundary_route = " ".join(f.read().split())
            assert boundary_route == "ip route add 10.99.0.0/16 via 192.168.50.20 dev verifyif37", boundary_route

            env["MOCK_DF_AVAILABLE"] = "1048577"
            env["MOCK_IFACE"] = "verifyif84"
            sufficient = subprocess.run(
                [script, "192.168.50.20"], env=env,
                capture_output=True, timeout=60
            )
            assert sufficient.returncode == 0, sufficient.stderr.decode(errors="replace")

        assert os.path.exists(restored_path), "The script did not restore the payload when free space exceeded 1 GB"
        with open(route_path) as f:
            final_route = " ".join(f.read().split())
        assert final_route == "ip route add 10.99.0.0/16 via 192.168.50.20 dev verifyif84", final_route

        with open(df_log) as f:
            df_calls = f.read().splitlines()
        assert len(df_calls) >= 2, "The script did not use df for both valid invocations"
        assert all("/home/user" in call.split() for call in df_calls[-2:]), "df must check the /home/user filesystem"
        with open(ip_log) as f:
            ip_calls = f.read().splitlines()
        assert len(ip_calls) >= 2, "The script did not query ip to discover the default interface"


def test_route_command():
    path = "/home/user/route_command.txt"
    assert os.path.exists(path), f"File {path} not found. The script was supposed to create it."
    with open(path, "r") as f:
        content = f.read().strip()

    expected_prefix = "ip route add 10.99.0.0/16 via 192.168.50.20"
    assert content.startswith(expected_prefix), f"Incorrect route command. Expected it to start with '{expected_prefix}', but got: {content}"


def test_setup_restore_executable():
    path = "/home/user/setup_restore.sh"
    assert os.path.exists(path), f"File {path} not found."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_restored_tar():
    tar_path = "/home/user/restored.tar"
    payload_path = "/app/backup_payload.dat"
    oracle_path = "/app/bin/cipher_oracle"

    assert os.path.exists(tar_path), f"File {tar_path} not found. The restore script may not have run successfully."

    with open(payload_path, "rb") as f:
        payload_data = f.read()

    oracle_proc = subprocess.run([oracle_path], input=payload_data, capture_output=True)
    expected_data = oracle_proc.stdout

    with open(tar_path, "rb") as f:
        actual_data = f.read()

    assert actual_data == expected_data, "Restored tar file contents do not match the expected unobfuscated data."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
