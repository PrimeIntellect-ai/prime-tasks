#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import subprocess
import tempfile

ORACLE_PATH = "/app/logistic_sim"
AGENT_PATH = "/home/user/py_sim.py"
N_ITERATIONS = 1000


def test_py_sim_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."


def _demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} does not exist."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable."

    rng = random.SystemRandom()
    cases = []
    for _ in range(N_ITERATIONS):
        y0 = rng.uniform(0.1, 10.0)
        r = rng.uniform(0.1, 2.0)
        K = rng.uniform(10.0, 100.0)
        dt = rng.uniform(0.01, 0.5)
        n_steps = rng.randint(1, 200)
        cases.append([
            f"{y0:.6f}", f"{r:.6f}", f"{K:.6f}", f"{dt:.6f}", str(n_steps)
        ])

    expected = []
    for args in cases:
        oracle_res = subprocess.run(
            [ORACLE_PATH] + args, capture_output=True, text=True
        )
        assert oracle_res.returncode == 0, (
            f"Oracle failed on args {args}:\n{oracle_res.stderr}"
        )
        expected.append(oracle_res.stdout.strip())

    # Keep the instructed oracle path present, but make it inaccessible to the
    # unprivileged account used to execute the submitted script.
    os.chmod(ORACLE_PATH, 0o700)

    # Install an immutable audit hook which prevents the submitted Python
    # process from launching a copied executable or contacting an oracle service.
    guard_dir = tempfile.mkdtemp(prefix="py_sim_guard_")
    guard_path = os.path.join(guard_dir, "sitecustomize.py")
    with open(guard_path, "w", encoding="utf-8") as guard:
        guard.write('''import sys\n\ndef _guard(event, args):\n    if (event in {"subprocess.Popen", "os.system", "os.fork", "os.forkpty", "ctypes.dlopen"}\n            or event.startswith("os.exec")\n            or event.startswith("os.spawn")\n            or event.startswith("os.posix_spawn")\n            or event.startswith("socket.")):\n        raise PermissionError("external execution and oracle IPC are disabled")\n\nsys.addaudithook(_guard)\n''')
    os.chmod(guard_path, 0o444)
    os.chmod(guard_dir, 0o555)

    agent_env = os.environ.copy()
    agent_env["PYTHONPATH"] = guard_dir

    for i, (args, oracle_out) in enumerate(zip(cases, expected), 1):
        agent_res = subprocess.run(
            ["python3", AGENT_PATH] + args,
            capture_output=True,
            text=True,
            cwd="/home/user",
            env=agent_env,
            preexec_fn=_demote_to_user,
        )
        assert agent_res.returncode == 0, (
            f"Agent script failed on args {args}:\n{agent_res.stderr}"
        )
        agent_out = agent_res.stdout.strip()
        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i}.\n"
            f"Arguments: y0={args[0]}, r={args[1]}, K={args[2]}, "
            f"dt={args[3]}, n_steps={args[4]}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
