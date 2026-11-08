#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/home/user/fw_policy_oracle"
PAYLOAD_PATH = "/home/user/evasion_payload.py"
VAULT_PATH = "/app/vault.zip"


def generate_random_ip(rng):
    choice = rng.random()
    if choice < 0.33:
        return f"10.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}"
    if choice < 0.66:
        return f"192.168.{rng.randint(0, 255)}.{rng.randint(0, 255)}"
    return f"{rng.randint(1, 223)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}"


def generate_random_port(rng):
    if rng.random() < 0.5:
        return rng.randint(1, 1023)
    return rng.randint(1024, 65535)


def generate_fuzz_input(rng):
    pairs = [
        f"{generate_random_ip(rng)}:{generate_random_port(rng)}"
        for _ in range(rng.randint(1, 5))
    ]
    return ";".join(pairs)


def derived_output(inp):
    lines = []
    for token in inp.split(";"):
        ip, port_text = token.split(":", 1)
        port = int(port_text)
        if ip.startswith("10."):
            lines.append(f"iptables -A INPUT -s {ip} -p tcp --dport {port} -j ACCEPT\n")
        elif port < 1024:
            lines.append(
                f"iptables -A INPUT -s {ip} -p tcp --dport {port} "
                "-j REJECT --reject-with tcp-reset\n"
            )
        else:
            lines.append(f"iptables -A INPUT -s {ip} -p tcp --dport {port} -j DROP\n")
    return "".join(lines)


def test_oracle_extracted_and_executable():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} is missing. Did you extract the vault?"
    st = os.stat(ORACLE_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Oracle binary {ORACLE_PATH} is not executable by the user."
    with open(ORACLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Oracle {ORACLE_PATH} is not an ELF binary."


def test_evasion_payload_exists():
    assert os.path.isfile(PAYLOAD_PATH), f"Evasion payload {PAYLOAD_PATH} is missing."


def test_fuzz_equivalence():
    if not os.path.isfile(ORACLE_PATH) or not os.path.isfile(PAYLOAD_PATH):
        pytest.skip("Prerequisite files are missing.")

    rng = secrets.SystemRandom()
    inputs = [
        "10.0.0.1:1",
        "10.255.255.255:65535",
        "192.168.1.1:1023",
        "192.168.1.1:1024",
        "1.2.3.4:80;10.2.3.4:8080;223.255.255.255:65535",
    ]
    inputs.extend(generate_fuzz_input(rng) for _ in range(250))

    # Exercise the extracted oracle and independently verify its behavior first.
    oracle_outputs = []
    for inp in inputs:
        oracle_proc = subprocess.run(
            [ORACLE_PATH, inp], capture_output=True, text=True, timeout=5
        )
        oracle_out = oracle_proc.stdout
        expected = derived_output(inp)
        assert oracle_out == expected, f"Extracted oracle produced unexpected output for '{inp}'."
        oracle_outputs.append(oracle_out)

    sandbox = tempfile.mkdtemp(prefix="payload-check-")
    os.chmod(sandbox, 0o755)
    sandbox_payload = os.path.join(sandbox, "evasion_payload.py")
    sandbox_runner = os.path.join(sandbox, "runner.py")
    shutil.copyfile(PAYLOAD_PATH, sandbox_payload)
    os.chmod(sandbox_payload, 0o644)

    runner_source = r'''import os
import runpy
import sys

payload = os.path.realpath(sys.argv[1])
argument = sys.argv[2]
allowed_files = {payload, os.path.realpath(__file__)}
allowed_prefixes = ("/usr/lib/", "/usr/local/lib/", "/lib/")

def audit(event, args):
    if event == "open":
        path = args[0]
        if isinstance(path, int):
            return
        if isinstance(path, bytes):
            path = os.fsdecode(path)
        real = os.path.realpath(path)
        if real not in allowed_files and not real.startswith(allowed_prefixes):
            raise PermissionError("standalone payload may not read external files")
    if (event.startswith("subprocess.") or event.startswith("ctypes.") or
            event.startswith("socket.") or event in {
                "os.system", "os.posix_spawn", "os.posix_spawnp",
                "os.exec", "os.spawn", "os.fork", "os.forkpty"
            } or event.startswith("os.exec") or event.startswith("os.spawn")):
        raise PermissionError("standalone payload may not invoke external code")

sys.addaudithook(audit)
sys.argv = [payload, argument]
runpy.run_path(payload, run_name="__main__")
'''
    with open(sandbox_runner, "w") as f:
        f.write(runner_source)
    os.chmod(sandbox_runner, 0o644)

    oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
    vault_mode = stat.S_IMODE(os.stat(VAULT_PATH).st_mode) if os.path.exists(VAULT_PATH) else None
    nobody = pwd.getpwnam("nobody")

    def drop_privileges():
        os.setgroups([])
        os.setgid(nobody.pw_gid)
        os.setuid(nobody.pw_uid)

    try:
        # Make the known oracle and encrypted source unavailable while payloads run.
        os.chmod(ORACLE_PATH, 0)
        if vault_mode is not None:
            os.chmod(VAULT_PATH, 0)

        clean_env = {
            "PATH": "/usr/bin:/bin",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        }
        for inp, oracle_out in zip(inputs, oracle_outputs):
            payload_proc = subprocess.run(
                ["python3", "-I", sandbox_runner, sandbox_payload, inp],
                cwd=sandbox,
                env=clean_env,
                preexec_fn=drop_privileges,
                capture_output=True,
                text=True,
                timeout=5,
            )
            payload_out = payload_proc.stdout
            assert oracle_out == payload_out, (
                f"Output mismatch on input: '{inp}'\n\n"
                f"=== Oracle Output ===\n{oracle_out}\n"
                f"=== Payload Output ===\n{payload_out}\n"
                "Payload must exactly match the oracle's standard output, including newlines."
            )
    finally:
        os.chmod(ORACLE_PATH, oracle_mode)
        if vault_mode is not None:
            os.chmod(VAULT_PATH, vault_mode)
        shutil.rmtree(sandbox, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
