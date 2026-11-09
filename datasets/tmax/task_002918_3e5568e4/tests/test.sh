#!/bin/bash
set -e
mkdir -p /logs/verifier

# The oracle remains available during the analysis phase, as required by the
# task, but final submissions may not invoke it during verification.
chown root:root /app/csv_processor
chmod 700 /app/csv_processor

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import shutil
import signal
import subprocess
import tempfile
import uuid
import pytest

ORACLE_PATH = "/app/csv_processor"
AGENT_PATH = "/home/user/process.sh"

# Executables suitable for a Bash/standard-Unix-tools implementation. Every
# exec performed by the submission is traced, so copied or delegated binaries
# outside this set are rejected.
ALLOWED_COMMANDS = {
    "bash", "sh", "dash", "awk", "gawk", "sort", "grep", "head", "tail",
    "sed", "cut", "tr", "paste", "join", "uniq", "wc", "cat", "tac",
    "printf", "echo", "expr", "test", "[", "env", "dirname", "basename",
    "mktemp", "rm", "mkdir", "rmdir", "touch", "readlink", "realpath",
    "find", "xargs", "tee", "comm", "nl", "fold", "fmt", "od", "stat",
    "seq", "split", "csplit", "sleep", "true", "false", "cp", "mv",
    "chmod", "stdbuf"
}
ALLOWED_EXES = set()
for command in ALLOWED_COMMANDS:
    path = shutil.which(command)
    if path:
        ALLOWED_EXES.add(os.path.realpath(path))

libc = ctypes.CDLL(None, use_errno=True)
PTRACE_TRACEME = 0
PTRACE_CONT = 7
PTRACE_SETOPTIONS = 0x4200
PTRACE_O_TRACEFORK = 0x02
PTRACE_O_TRACEVFORK = 0x04
PTRACE_O_TRACECLONE = 0x08
PTRACE_O_TRACEEXEC = 0x10
PTRACE_O_EXITKILL = 0x00100000
PTRACE_EVENT_EXEC = 4
WAIT_ALL = 0x40000000
TRACE_OPTIONS = (
    PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK | PTRACE_O_TRACECLONE |
    PTRACE_O_TRACEEXEC | PTRACE_O_EXITKILL
)


def _ptrace(request, pid, addr=0, data=0):
    result = libc.ptrace(request, pid, ctypes.c_void_p(addr), ctypes.c_void_p(data))
    if result == -1:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
    return result


def run_agent_traced(csv_path):
    """Run the submission as the unprivileged agent while tracing every exec."""
    stdout_file = tempfile.TemporaryFile()
    stderr_file = tempfile.TemporaryFile()
    user = __import__("pwd").getpwnam("user")

    pid = os.fork()
    if pid == 0:
        try:
            os.setsid()
            os.dup2(stdout_file.fileno(), 1)
            os.dup2(stderr_file.fileno(), 2)
            _ptrace(PTRACE_TRACEME, 0)
            os.kill(os.getpid(), signal.SIGSTOP)
            os.setgroups([])
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)
            os.execv("/bin/bash", ["bash", AGENT_PATH, csv_path])
        except BaseException:
            os._exit(127)

    _, status = os.waitpid(pid, 0)
    assert os.WIFSTOPPED(status), "Failed to initialize submission tracing"
    _ptrace(PTRACE_SETOPTIONS, pid, 0, TRACE_OPTIONS)
    _ptrace(PTRACE_CONT, pid, 0, 0)

    main_returncode = None
    forbidden_exec = None
    live = {pid}

    while live:
        try:
            child, status = os.waitpid(-1, WAIT_ALL)
        except ChildProcessError:
            break

        if os.WIFEXITED(status):
            live.discard(child)
            if child == pid:
                main_returncode = os.WEXITSTATUS(status)
            continue
        if os.WIFSIGNALED(status):
            live.discard(child)
            if child == pid:
                main_returncode = -os.WTERMSIG(status)
            continue
        if not os.WIFSTOPPED(status):
            continue

        live.add(child)
        stop_signal = os.WSTOPSIG(status)
        event = status >> 16

        if event == PTRACE_EVENT_EXEC:
            try:
                executable = os.path.realpath(os.readlink(f"/proc/{child}/exe"))
            except OSError:
                executable = "<unknown>"
            if executable not in ALLOWED_EXES:
                forbidden_exec = executable
                try:
                    os.killpg(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            deliver = 0
        elif stop_signal in (signal.SIGSTOP, signal.SIGTRAP):
            deliver = 0
        else:
            deliver = stop_signal

        try:
            _ptrace(PTRACE_CONT, child, 0, deliver)
        except OSError:
            pass

    stdout_file.seek(0)
    stderr_file.seek(0)
    stdout = stdout_file.read().decode("utf-8", errors="replace")
    stderr = stderr_file.read().decode("utf-8", errors="replace")
    stdout_file.close()
    stderr_file.close()

    if forbidden_exec is not None:
        stderr += f"\nForbidden executable invoked by submission: {forbidden_exec}\n"
        return subprocess.CompletedProcess([], 126, stdout, stderr)
    if main_returncode is None:
        main_returncode = 1
    return subprocess.CompletedProcess([], main_returncode, stdout, stderr)


def generate_csv(filepath, num_rows):
    departments = ["Sales", "Engineering", "HR", "Marketing", "Support", "Finance", "Legal"]
    statuses = ["ACTIVE", "INACTIVE", "PENDING", "ARCHIVED"]

    with open(filepath, 'w') as f:
        f.write("id,department,status,revenue,cost,timestamp\n")
        for _ in range(num_rows):
            row_id = str(uuid.uuid4())
            dept = random.choice(departments)
            status = random.choice(statuses)
            revenue = round(random.uniform(0.0, 10000.0), 2)
            cost = round(random.uniform(0.0, 10000.0), 2)
            ts = f"2023-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}T{random.randint(0, 23):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}Z"
            f.write(f"{row_id},{dept},{status},{revenue},{cost},{ts}\n")


def test_agent_script_exists():
    """Verify the agent's script exists and is executable."""
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script at {AGENT_PATH} is not executable"


def test_fuzz_equivalence():
    """Fuzz both the oracle and the agent script to ensure exact equivalence."""
    random.seed(42)
    num_tests = 50

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o755)
        for i in range(num_tests):
            num_rows = random.randint(0, 1000)
            csv_path = os.path.join(tmpdir, f"test_{i}.csv")
            generate_csv(csv_path, num_rows)
            os.chmod(csv_path, 0o644)

            oracle_cmd = [ORACLE_PATH, csv_path]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            agent_res = run_agent_traced(csv_path)

            assert oracle_res.returncode == 0, f"Oracle failed on test case {i}:\n{oracle_res.stderr}"
            assert agent_res.returncode == 0, f"Agent script failed on test case {i}:\n{agent_res.stderr}"

            if oracle_res.stdout != agent_res.stdout:
                with open(csv_path, 'r') as f:
                    input_data = f.read()

                display_input = input_data if len(input_data) < 1000 else input_data[:1000] + "\n... [truncated]"

                pytest.fail(
                    f"Output mismatch on test case {i} (Rows: {num_rows}).\n\n"
                    f"=== Input CSV ===\n{display_input}\n\n"
                    f"=== Oracle Output ===\n{oracle_res.stdout}\n"
                    f"=== Agent Output ===\n{agent_res.stdout}\n"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
