#!/bin/bash
mkdir -p /logs/verifier

cat << 'TRACER_EOF' > /tmp/noexec_tracer.c
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) return 126;

    pid_t root = fork();
    if (root < 0) return 126;
    if (root == 0) {
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) < 0) _exit(126);
        raise(SIGSTOP);
        if (argc >= 3)
            execl("/bin/bash", "bash", argv[1], argv[2], (char *)NULL);
        else
            execl("/bin/bash", "bash", argv[1], (char *)NULL);
        _exit(126);
    }

    int status;
    if (waitpid(root, &status, 0) < 0 || !WIFSTOPPED(status)) return 126;

    long options = PTRACE_O_TRACEEXEC | PTRACE_O_TRACEFORK |
                   PTRACE_O_TRACEVFORK | PTRACE_O_TRACECLONE;
    ptrace(PTRACE_SETOPTIONS, root, NULL, (void *)options);
    ptrace(PTRACE_CONT, root, NULL, NULL);

    int root_exec_seen = 0;
    int forbidden_exec = 0;
    int root_result = 126;
    int root_finished = 0;

    for (;;) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) {
            if (errno == EINTR) continue;
            if (errno == ECHILD) break;
            return 126;
        }

        if (WIFEXITED(status)) {
            if (pid == root) {
                root_result = WEXITSTATUS(status);
                root_finished = 1;
            }
            continue;
        }
        if (WIFSIGNALED(status)) {
            if (pid == root) {
                root_result = 128 + WTERMSIG(status);
                root_finished = 1;
            }
            continue;
        }
        if (!WIFSTOPPED(status)) continue;

        unsigned int event = ((unsigned int)status) >> 16;
        int sig = WSTOPSIG(status);

        if (event == PTRACE_EVENT_EXEC) {
            if (pid == root && !root_exec_seen)
                root_exec_seen = 1;
            else
                forbidden_exec = 1;
        }

        ptrace(PTRACE_SETOPTIONS, pid, NULL, (void *)options);
        ptrace(PTRACE_CONT, pid, NULL,
               (void *)(long)((sig == SIGTRAP || sig == SIGSTOP) ? 0 : sig));
    }

    if (!root_finished || forbidden_exec) return 125;
    return root_result;
}
TRACER_EOF

gcc -O2 /tmp/noexec_tracer.c -o /tmp/noexec_tracer >/tmp/noexec_build.log 2>&1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shlex
import stat
import subprocess
import tempfile
import time


def generate_payload():
    num_instructions = random.randint(4, 100)
    payload = ""
    for _ in range(num_instructions):
        if random.random() < 0.05:
            payload += "FF"
            break

        op = random.choice(["01", "02", "03", "04", "05"])
        payload += op
        if op in ["01", "02", "05"]:
            payload += f"{random.randint(0, 255):02X}"
    return payload


def model(payload):
    acc = 0
    output = []
    i = 0
    while i < len(payload):
        if len(payload) - i < 2:
            break
        op = int(payload[i:i + 2], 16)
        i += 2
        if op in (0x01, 0x02, 0x05):
            if i + 2 > len(payload):
                break
            arg = int(payload[i:i + 2], 16)
            i += 2
            if op == 0x01:
                acc = (acc + arg) & 0xFF
            elif op == 0x02:
                acc = (acc - arg) & 0xFF
            else:
                output.append("OK\n" if acc == arg else "FAIL\n")
        elif op == 0x03:
            acc = (acc << 1) & 0xFF
        elif op == 0x04:
            acc ^= 0xA5
        elif op == 0xFF:
            output.append(f"FINAL: {acc:02X}\n")
            break
    return "".join(output)


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_chksum_bin"
    agent_path = "/home/user/bash_parser.sh"

    assert os.path.isfile(oracle_path), f"Oracle program {oracle_path} is missing."
    assert os.path.isfile(agent_path), f"Agent script {agent_path} is missing."

    random.seed(42)

    for i in range(1000):
        payload = generate_payload()

        oracle_res = subprocess.run([oracle_path, payload], capture_output=True, text=True)
        agent_res = subprocess.run(["/bin/bash", agent_path, payload], capture_output=True, text=True)

        assert oracle_res.returncode == agent_res.returncode, (
            f"Exit code mismatch on payload: {payload}\n"
            f"Oracle exit code: {oracle_res.returncode}\n"
            f"Agent exit code: {agent_res.returncode}"
        )
        assert oracle_res.stdout == agent_res.stdout, (
            f"Stdout mismatch on payload: {payload}\n"
            f"Oracle stdout:\n{oracle_res.stdout}\n"
            f"Agent stdout:\n{agent_res.stdout}"
        )


def test_parser_is_pure_bash_and_matches_derived_answers():
    agent_path = "/home/user/bash_parser.sh"
    tracer = "/tmp/noexec_tracer"

    st = os.lstat(agent_path)
    assert stat.S_ISREG(st.st_mode), "bash_parser.sh must be a regular Bash source file."
    assert os.path.isfile(tracer) and os.access(tracer, os.X_OK), "Execution tracer was not built."

    with open(agent_path, "rb") as f:
        source = f.read()
    assert b"legacy_chksum_bin" not in source, "The Bash implementation must not invoke the legacy binary."

    directed = [
        "FF",
        "01010501FF",
        "010202010501FF",
        "02010305FF04FF",
        "01FF03FF",
        "04FF",
        "01FE0303010204FF",
        "050001010501FF",
        "0101",
        "01",
        "020",
        "03",
        "040500",
        "7F0101FF",
        "0101FF04FF",
    ]

    rng = random.Random(913764)
    for _ in range(150):
        chunks = []
        for _ in range(rng.randint(5, 40)):
            op = rng.choice([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x7F, 0xFE])
            chunks.append(f"{op:02X}")
            if op in (0x01, 0x02, 0x05):
                chunks.append(f"{rng.randrange(256):02X}")
        if rng.random() < 0.8:
            chunks.append("FF")
        directed.append("".join(chunks))

    for payload in directed:
        result = subprocess.run(
            [tracer, agent_path, payload], capture_output=True, text=True, timeout=5
        )
        assert result.returncode != 125, (
            f"bash_parser.sh executed another program on payload {payload}; "
            "the implementation must be pure Bash."
        )
        assert result.returncode == 0, (
            f"Unexpected exit status {result.returncode} on payload {payload}.\n"
            f"stderr: {result.stderr}"
        )
        assert result.stdout == model(payload), (
            f"Derived-answer mismatch on payload {payload}.\n"
            f"Expected: {model(payload)!r}\nActual: {result.stdout!r}"
        )


def test_benchmark_actually_runs_both_programs_on_random_payloads():
    benchmark_script = "/home/user/benchmark.sh"
    benchmark_log = "/home/user/benchmark_results.log"
    legacy_path = "/app/legacy_chksum_bin"
    parser_path = "/home/user/bash_parser.sh"

    assert os.path.isfile(benchmark_script), f"Benchmark script {benchmark_script} is missing."
    assert os.path.isfile(benchmark_log), f"Benchmark log {benchmark_log} is missing."

    with open(benchmark_log, "rb") as f:
        before = f.read()

    tempdir = tempfile.mkdtemp(prefix="benchmark_verify_")
    legacy_backup = os.path.join(tempdir, "legacy.real")
    parser_backup = os.path.join(tempdir, "parser.real")
    legacy_calls = os.path.join(tempdir, "legacy.calls")
    parser_calls = os.path.join(tempdir, "parser.calls")

    os.replace(legacy_path, legacy_backup)
    os.replace(parser_path, parser_backup)
    try:
        legacy_wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {shlex.quote(legacy_calls)}
/bin/sleep 0.01
exec {shlex.quote(legacy_backup)} "$@"
'''
        parser_wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {shlex.quote(parser_calls)}
/bin/sleep 0.02
exec /bin/bash {shlex.quote(parser_backup)} "$@"
'''
        with open(legacy_path, "w") as f:
            f.write(legacy_wrapper)
        with open(parser_path, "w") as f:
            f.write(parser_wrapper)
        os.chmod(legacy_path, 0o755)
        os.chmod(parser_path, 0o755)

        started = time.monotonic()
        run = subprocess.run(
            ["/bin/bash", benchmark_script], capture_output=True, text=True, timeout=30
        )
        elapsed = time.monotonic() - started
        assert run.returncode == 0, f"benchmark.sh failed: {run.stderr}"
    finally:
        if os.path.exists(legacy_path):
            os.unlink(legacy_path)
        if os.path.exists(parser_path):
            os.unlink(parser_path)
        os.replace(legacy_backup, legacy_path)
        os.replace(parser_backup, parser_path)

    def read_calls(path):
        if not os.path.exists(path):
            return []
        with open(path) as f:
            return [line.rstrip("\n") for line in f]

    legacy_payloads = read_calls(legacy_calls)
    bash_payloads = read_calls(parser_calls)
    assert len(legacy_payloads) == 50, f"Legacy binary was run {len(legacy_payloads)} times, not 50."
    assert len(bash_payloads) == 50, f"Bash parser was run {len(bash_payloads)} times, not 50."
    assert legacy_payloads == bash_payloads, "Both implementations must be benchmarked on the same payloads."

    for payload in legacy_payloads:
        assert re.fullmatch(r"[0-9A-Fa-f]+", payload), f"Invalid hex payload: {payload!r}"
        assert len(payload) % 2 == 0, f"Payload has a partial byte: {payload!r}"
        assert 10 <= len(payload) // 2 <= 30, f"Payload is outside the 10-30 byte range: {payload!r}"
    assert len(set(legacy_payloads)) >= 40, "The benchmark did not generate sufficiently varied random payloads."

    with open(benchmark_log, "rb") as f:
        after = f.read()
    assert after.startswith(before), "benchmark.sh must append to, not replace, benchmark_results.log."
    appended = after[len(before):].decode("utf-8")
    new_lines = [line for line in appended.splitlines() if line.strip()]
    assert len(new_lines) == 1, "Each benchmark run must append exactly one report line."

    match = re.fullmatch(r"Legacy: ([0-9]+(?:\.[0-9]+)?)s \| Bash: ([0-9]+(?:\.[0-9]+)?)s", new_lines[0])
    assert match, f"Benchmark report format is incorrect: {new_lines[0]!r}"
    legacy_time, bash_time = map(float, match.groups())
    assert math.isfinite(legacy_time) and math.isfinite(bash_time)
    assert legacy_time >= 0.35, "Reported legacy time does not reflect the 50 instrumented executions."
    assert bash_time >= 0.80, "Reported Bash time does not reflect the 50 instrumented executions."
    assert legacy_time <= elapsed + 0.5 and bash_time <= elapsed + 0.5, "Reported times are not plausible measurements."
    assert elapsed >= 1.15, "The benchmark did not sequentially execute both sets of instrumented runs."


def test_benchmark_artifacts():
    benchmark_script = "/home/user/benchmark.sh"
    benchmark_log = "/home/user/benchmark_results.log"

    assert os.path.isfile(benchmark_script), f"Benchmark script {benchmark_script} is missing."
    assert os.path.isfile(benchmark_log), f"Benchmark log {benchmark_log} is missing."

    with open(benchmark_log, "r") as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) >= 1, "Benchmark log is empty."

    last_line = lines[-1]
    pattern = r"^Legacy: [0-9.]+s \| Bash: [0-9.]+s$"
    assert re.match(pattern, last_line), f"Benchmark log format is incorrect. Found: {last_line}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
