#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import platform
import random
import re
import shutil
import stat
import string
import subprocess
import tempfile


def test_sshd_config_hardened():
    config_path = "/home/user/sshd_config"
    assert os.path.exists(config_path), f"Missing SSH config file: {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    # Parse active configuration lines
    lines = [line.strip() for line in content.splitlines()
             if line.strip() and not line.strip().startswith("#")]

    # Check required SSH hardening directives
    assert "PasswordAuthentication no" in lines, \
        "PasswordAuthentication is not set to 'no'"
    assert "HostKeyAlgorithms ssh-ed25519" in lines, \
        "HostKeyAlgorithms is not restricted to 'ssh-ed25519'"


def expected_output(seed):
    value = 0x5A
    for byte in os.fsencode(seed):
        value ^= byte
        value = ((value << 1) | (value >> 7)) & 0xFF
    return f"{value:02x}\n".encode("ascii")


def install_network_seccomp():
    """Prevent a submitted Bash script from consulting a helper over a socket."""
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        denied = (41, 42, 53)  # socket, connect, socketpair
    elif machine in ("aarch64", "arm64"):
        denied = (198, 203, 199)
    else:
        raise RuntimeError(f"Unsupported architecture for sandbox: {machine}")

    class SockFilter(ctypes.Structure):
        _fields_ = [
            ("code", ctypes.c_ushort),
            ("jt", ctypes.c_ubyte),
            ("jf", ctypes.c_ubyte),
            ("k", ctypes.c_uint32),
        ]

    class SockFprog(ctypes.Structure):
        _fields_ = [
            ("len", ctypes.c_ushort),
            ("filter", ctypes.POINTER(SockFilter)),
        ]

    BPF_LD_W_ABS = 0x20
    BPF_JMP_JEQ_K = 0x15
    BPF_RET_K = 0x06
    SECCOMP_RET_ALLOW = 0x7FFF0000
    SECCOMP_RET_ERRNO = 0x00050000
    PR_SET_NO_NEW_PRIVS = 38
    PR_SET_SECCOMP = 22
    SECCOMP_MODE_FILTER = 2

    instructions = [SockFilter(BPF_LD_W_ABS, 0, 0, 0)]
    for syscall_number in denied:
        instructions.append(SockFilter(BPF_JMP_JEQ_K, 0, 1, syscall_number))
        instructions.append(SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | 1))
    instructions.append(SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ALLOW))

    array_type = SockFilter * len(instructions)
    filter_array = array_type(*instructions)
    program = SockFprog(len(instructions), filter_array)
    libc = ctypes.CDLL(None, use_errno=True)

    if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
    if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER,
                  ctypes.byref(program), 0, 0) != 0:
        raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")


def make_bash_jail(agent_path):
    jail = tempfile.mkdtemp(prefix="keygen-jail-")
    os.chmod(jail, 0o755)

    bash_path = "/bin/bash"
    paths = {bash_path}
    ldd = subprocess.run(["ldd", bash_path], capture_output=True, text=True,
                         check=True)
    for line in ldd.stdout.splitlines():
        match = re.search(r"(/[^^\s()]+)", line)
        if match:
            paths.add(match.group(1))

    for source in paths:
        destination = os.path.join(jail, source.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(source, destination, follow_symlinks=True)

    os.makedirs(os.path.join(jail, "dev"), exist_ok=True)
    null_path = os.path.join(jail, "dev", "null")
    open(null_path, "wb").close()
    os.chmod(null_path, 0o666)

    submission = os.path.join(jail, "submission.sh")
    shutil.copyfile(agent_path, submission)
    os.chmod(submission, 0o555)
    return jail


def test_keygen_fuzz_equivalence():
    oracle_path = "/app/keygen_legacy"
    agent_path = "/home/user/keygen_recreated.sh"

    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"
    mode = os.lstat(agent_path).st_mode
    assert stat.S_ISREG(mode), "Agent submission must be a regular Bash script"

    jail = make_bash_jail(agent_path)
    chroot = shutil.which("chroot")
    assert chroot is not None, "chroot utility unavailable"

    fixed_inputs = [
        "", "a", "A", "0", "ds92", "hello world", "-n", "--help",
        "!@#$%^&*()", "with\ttab", "with\nnewline", "x" * 64,
    ]

    # Unpredictable cases prevent a submission from hard-coding the verifier corpus.
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + string.punctuation + " "
    fuzz_inputs = fixed_inputs + [
        "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 64)))
        for _ in range(1000)
    ]

    oracle_env = os.environ.copy()
    oracle_env["ACTIVATION_PHRASE"] = "ds92"
    agent_env = {"PATH": "/bin", "HOME": "/", "LC_ALL": "C"}

    try:
        for fuzz_input in fuzz_inputs:
            oracle_proc = subprocess.run(
                [oracle_path, fuzz_input],
                env=oracle_env,
                capture_output=True,
                timeout=3,
            )
            assert oracle_proc.returncode == 0, \
                f"Oracle failed on input {fuzz_input!r}: {oracle_proc.stderr!r}"

            # Execute only the submitted file and Bash inside an isolated root. The
            # legacy binary, agent-created copies, and external utilities are absent.
            agent_proc = subprocess.run(
                [chroot, "--userspec=65534:65534", jail,
                 "/bin/bash", "--noprofile", "--norc",
                 "/submission.sh", fuzz_input],
                env=agent_env,
                capture_output=True,
                timeout=3,
                preexec_fn=install_network_seccomp,
            )
            assert agent_proc.returncode == 0, \
                f"Agent script failed on input {fuzz_input!r}: {agent_proc.stderr!r}"

            # Preserve the original oracle-equivalence assertion.
            assert oracle_proc.stdout.strip() == agent_proc.stdout.strip(), \
                (f"Mismatch on input {fuzz_input!r}. Oracle: "
                 f"{oracle_proc.stdout!r}, Agent: {agent_proc.stdout!r}")

            # Independently derive the answer and require byte-exact stdout.
            expected = expected_output(fuzz_input)
            assert oracle_proc.stdout == expected, "Oracle disagrees with derived answer"
            assert agent_proc.stdout == expected, \
                f"Agent output is not byte-exact for input {fuzz_input!r}"
    finally:
        shutil.rmtree(jail, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
