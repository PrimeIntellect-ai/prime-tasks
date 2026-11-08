#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/noexec_runner.c
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 2) return 126;

    pid_t root = fork();
    if (root < 0) return 126;
    if (root == 0) {
        setpgid(0, 0);
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) < 0) _exit(126);
        raise(SIGSTOP);
        execvp(argv[1], &argv[1]);
        _exit(127);
    }

    int status;
    if (waitpid(root, &status, 0) != root || !WIFSTOPPED(status)) return 126;

    long opts = PTRACE_O_TRACEEXEC | PTRACE_O_TRACEFORK |
                PTRACE_O_TRACEVFORK | PTRACE_O_TRACECLONE |
                PTRACE_O_EXITKILL;
    if (ptrace(PTRACE_SETOPTIONS, root, 0, opts) < 0) return 126;
    ptrace(PTRACE_CONT, root, 0, 0);

    int initial_exec_seen = 0;
    int root_result = 126;
    int root_done = 0;
    int forbidden_exec = 0;

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
                root_done = 1;
            }
            continue;
        }
        if (WIFSIGNALED(status)) {
            if (pid == root) {
                root_result = 128 + WTERMSIG(status);
                root_done = 1;
            }
            continue;
        }
        if (!WIFSTOPPED(status)) continue;

        unsigned event = ((unsigned)status) >> 16;
        int sig = WSTOPSIG(status);
        if (event == PTRACE_EVENT_EXEC) {
            if (pid == root && !initial_exec_seen) {
                initial_exec_seen = 1;
                ptrace(PTRACE_CONT, pid, 0, 0);
            } else {
                forbidden_exec = 1;
                kill(-root, SIGKILL);
                ptrace(PTRACE_KILL, pid, 0, 0);
            }
            continue;
        }

        if (forbidden_exec) {
            ptrace(PTRACE_KILL, pid, 0, 0);
            continue;
        }

        int deliver = (sig == SIGTRAP || sig == SIGSTOP) ? 0 : sig;
        ptrace(PTRACE_CONT, pid, 0, deliver);
    }

    if (forbidden_exec) {
        fprintf(stderr, "submission attempted to execute another program\n");
        return 125;
    }
    return root_done ? root_result : 126;
}
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import sqlite3
import subprocess

AGENT_SCRIPT = "/home/user/project_graph.py"
ORACLE_BIN = "/app/graph_materializer_bin"
RUNNER = "/tmp/noexec_runner"
DB_PATH = "/home/user/data.db"


def expected_output(payload):
    source = payload["source_table"] if "source_table" in payload else payload.get("source", "")
    target = payload["target_table"] if "target_table" in payload else payload.get("target", "")
    link = payload["relation_type"] if "relation_type" in payload else payload.get("link", "")

    if source == "Users" and target == "Departments":
        query = "SELECT Users.id, Departments.id, ? FROM Users JOIN Departments ON Users.dept_id = Departments.id;"
    elif source == "Users" and target == "Roles":
        query = "SELECT Users.id, Roles.id, ? FROM Users JOIN UserRoles ON Users.id = UserRoles.user_id JOIN Roles ON UserRoles.role_id = Roles.id;"
    elif source == "Users" and target == "Projects":
        query = "SELECT Users.id, Projects.id, ? FROM Users JOIN Projects ON Users.id = Projects.owner_id;"
    else:
        return ""

    with sqlite3.connect(DB_PATH) as db:
        rows = db.execute(query, (link,)).fetchall()
    return "".join(f"{source_id},{target_id},{edge_type}\n" for source_id, target_id, edge_type in rows)


def run_case(payload):
    input_json = json.dumps(payload).encode("utf-8")
    proc = subprocess.run(
        [RUNNER, "python3", AGENT_SCRIPT],
        input=input_json,
        capture_output=True,
        timeout=15,
    )
    assert proc.returncode == 0, (
        f"Return code mismatch for input {payload}: expected=0, agent={proc.returncode}.\n"
        f"Agent stderr: {proc.stderr.decode('utf-8', errors='replace')}"
    )
    actual = proc.stdout.decode("utf-8")
    expected = expected_output(payload)
    assert actual == expected, (
        f"Output mismatch for input {payload}.\n"
        f"Expected output (first 500 chars):\n{expected[:500]}\n"
        f"Agent output (first 500 chars):\n{actual[:500]}"
    )


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} not found."
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} not found."

    with open(AGENT_SCRIPT, "rb") as submitted, open(ORACLE_BIN, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submission is byte-identical to the reference binary."

    # The reference was available for reverse engineering, but must not remain
    # callable while the submitted replacement is being evaluated.
    os.remove(ORACLE_BIN)

    cases = []
    for target in ("Departments", "Roles", "Projects"):
        cases.append({
            "source_table": "Users",
            "target_table": target,
            "relation_type": f"CANONICAL_TO_{target}",
        })
        cases.append({
            "source": "Users",
            "target": target,
            "link": f"ALIAS_TO_{target}",
        })
        cases.append({
            "source_table": "Users",
            "target_table": target,
            "relation_type": f"PRIORITY_TO_{target}",
            "source": "Departments",
            "target": "Users",
            "link": "IGNORED_ALIAS",
        })

    random.seed(42)
    tables = ["Users", "Departments", "Roles", "Projects"]
    while len(cases) < 50:
        src = random.choice(tables)
        tgt = random.choice(tables)
        link = f"{src}_TO_{tgt}_{len(cases)}"
        if len(cases) % 2:
            cases.append({"source": src, "target": tgt, "link": link})
        else:
            cases.append({
                "source_table": src,
                "target_table": tgt,
                "relation_type": link,
            })

    for payload in cases:
        run_case(payload)
TEST_EOF

if gcc -O2 /tmp/noexec_runner.c -o /tmp/noexec_runner && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
