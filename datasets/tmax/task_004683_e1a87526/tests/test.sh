#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_python_sandboxed.py
import ctypes
import platform
import runpy
import sys

# Install an irreversible seccomp filter before loading the submission. The
# submitted Python program may perform normal file I/O, but may not delegate
# its work to any executable copied from the legacy compiler.
class SockFilter(ctypes.Structure):
    _fields_ = [("code", ctypes.c_ushort),
                ("jt", ctypes.c_ubyte),
                ("jf", ctypes.c_ubyte),
                ("k", ctypes.c_uint32)]

class SockFprog(ctypes.Structure):
    _fields_ = [("len", ctypes.c_ushort),
                ("filter", ctypes.POINTER(SockFilter))]

machine = platform.machine().lower()
if machine in ("x86_64", "amd64"):
    blocked = (59, 322)       # execve, execveat
elif machine in ("aarch64", "arm64"):
    blocked = (221, 281)      # execve, execveat
else:
    raise SystemExit("unsupported verification architecture")

BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06
SECCOMP_RET_ALLOW = 0x7fff0000
SECCOMP_RET_ERRNO = 0x00050000
EACCES = 13

instructions = [SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0)]
for syscall_number in blocked:
    instructions.append(SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, syscall_number))
    instructions.append(SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EACCES))
instructions.append(SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW))
program_array = (SockFilter * len(instructions))(*instructions)
program = SockFprog(len(instructions), program_array)

libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(38, 1, 0, 0, 0) != 0:  # PR_SET_NO_NEW_PRIVS
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(22, 2, ctypes.byref(program), 0, 0) != 0:  # PR_SET_SECCOMP
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = sys.argv[1:]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/doc_compiler"
AGENT_SCRIPT = "/home/user/py_compiler.py"
CONFIG_PATH = "/home/user/compiler_config.ini"
SANDBOX_RUNNER = "/tmp/run_python_sandboxed.py"

def generate_random_string(length):
    return ''.join(random.choices(string.printable, k=length)).encode('utf-8')

def generate_fuzz_inputs(num_cases=100):
    random.seed(42)
    cases = []
    for i in range(num_cases):
        case_type = random.random()

        if case_type < 0.10:
            magic = b"X89TDO\x00" if random.random() < 0.5 else b"random"
            content = magic + b"some_data"
            cases.append(("invalid_magic", content))
        elif case_type < 0.20:
            content = b"\x89TDOC\x00"
            num_records = random.randint(1, 10)
            for _ in range(num_records):
                rec_type = random.choice([0x01, 0x02, 0x03])
                length = random.randint(0, 50)
                payload = generate_random_string(length)
                content += bytes([rec_type]) + length.to_bytes(2, 'little') + payload
            cases.append(("truncated", content))
        elif case_type < 0.30:
            content = b"\x89TDOC\x00"
            num_records = random.randint(1, 10)
            for _ in range(num_records):
                rec_type = random.choice([0x01, 0x02, 0x03])
                length = random.randint(0, 50)
                payload = generate_random_string(length)
                content += bytes([rec_type]) + length.to_bytes(2, 'little') + payload

            invalid_type = random.choice([t for t in range(256) if t not in [0x01, 0x02, 0x03, 0xFF]])
            length = random.randint(0, 50)
            payload = generate_random_string(length)
            content += bytes([invalid_type]) + length.to_bytes(2, 'little') + payload
            cases.append(("invalid_type", content))
        else:
            content = b"\x89TDOC\x00"
            num_records = random.randint(1, 50)
            for _ in range(num_records):
                rec_type = random.choice([0x01, 0x02, 0x03])
                length = random.randint(0, 500)
                payload = generate_random_string(length)
                length = len(payload)
                content += bytes([rec_type]) + length.to_bytes(2, 'little') + payload
            content += b"\xFF"
            cases.append(("valid", content))

    return cases

def run_command(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} missing."

    inputs = generate_fuzz_inputs(100)
    prepared = []

    with tempfile.TemporaryDirectory() as tmpdir:
        # Derive all expected results first and retain them only in verifier
        # memory. Do not leave oracle output files beside agent-visible inputs.
        for i, (case_type, content) in enumerate(inputs):
            input_file = os.path.join(tmpdir, f"input_{i}.tdoc")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.md")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.md")

            with open(input_file, "wb") as f:
                f.write(content)

            render_hidden = random.choice([True, False])
            config_content = f"[Settings]\nrender_hidden={'true' if render_hidden else 'false'}\n"
            with open(CONFIG_PATH, "w") as f:
                f.write(config_content)

            oracle_code, oracle_stdout, oracle_stderr = run_command(
                [ORACLE_PATH, input_file, oracle_out]
            )
            oracle_file_exists = os.path.exists(oracle_out)
            oracle_file_content = None
            if oracle_file_exists:
                with open(oracle_out, "rb") as f:
                    oracle_file_content = f.read()
                os.unlink(oracle_out)

            prepared.append((case_type, input_file, agent_out, render_hidden,
                             config_content, oracle_code, oracle_stdout,
                             oracle_stderr, oracle_file_exists,
                             oracle_file_content))

        # The reference must not be available while submissions execute.
        os.unlink(ORACLE_PATH)

        for i, item in enumerate(prepared):
            (case_type, input_file, agent_out, render_hidden, config_content,
             oracle_code, oracle_stdout, oracle_stderr, oracle_file_exists,
             oracle_file_content) = item

            with open(CONFIG_PATH, "w") as f:
                f.write(config_content)

            agent_cmd = ["python3", SANDBOX_RUNNER, AGENT_SCRIPT,
                         input_file, agent_out]
            agent_code, agent_stdout, agent_stderr = run_command(agent_cmd)

            error_msg = f"Mismatch on test case {i} (type: {case_type}, render_hidden: {render_hidden}).\n"
            assert agent_code == oracle_code, error_msg + f"Exit code mismatch: Oracle={oracle_code}, Agent={agent_code}\nOracle stderr: {oracle_stderr}\nAgent stderr: {agent_stderr}"
            assert agent_stdout == oracle_stdout, error_msg + f"Stdout mismatch: Oracle={repr(oracle_stdout)}, Agent={repr(agent_stdout)}"
            assert agent_stderr == oracle_stderr, error_msg + f"Stderr mismatch: Oracle={repr(oracle_stderr)}, Agent={repr(agent_stderr)}"

            agent_file_exists = os.path.exists(agent_out)
            assert agent_file_exists == oracle_file_exists, error_msg + f"Output file existence mismatch: Oracle={oracle_file_exists}, Agent={agent_file_exists}"

            if oracle_file_exists:
                with open(agent_out, "rb") as f:
                    agent_file_content = f.read()
                assert agent_file_content == oracle_file_content, error_msg + "Output file content mismatch."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
