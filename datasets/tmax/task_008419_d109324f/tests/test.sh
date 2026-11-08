#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import stat
import subprocess
import tempfile

import pytest

REPO_PATH = "/home/user/deploy_repo.git"
HOOK_PATH = os.path.join(REPO_PATH, "hooks", "pre-receive")
LOG_PATH = "/home/user/monitoring_log.json"
MONITOR_PATH = "/home/user/legacy_monitor.py"


def run_cmd(cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env, shell=True,
                          capture_output=True, text=True)


def test_repo_and_hook_exist():
    assert os.path.isdir(REPO_PATH), f"Bare repository directory not found at {REPO_PATH}"

    res = run_cmd("git rev-parse --is-bare-repository", cwd=REPO_PATH)
    assert res.returncode == 0 and "true" in res.stdout, f"{REPO_PATH} is not a bare Git repository"

    assert os.path.isfile(HOOK_PATH), f"pre-receive hook not found at {HOOK_PATH}"
    assert os.access(HOOK_PATH, os.X_OK), f"pre-receive hook at {HOOK_PATH} is not executable"


def test_hook_is_python_and_uses_pexpect_spawn():
    source = open(HOOK_PATH, "r", encoding="utf-8").read()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"pre-receive hook is not valid Python: {exc}")

    pexpect_modules = set()
    spawn_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    pexpect_modules.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_names.add(alias.asname or "spawn")

    found_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in spawn_names:
            found_spawn = True
        if (isinstance(node.func, ast.Attribute)
                and node.func.attr == "spawn"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in pexpect_modules):
            found_spawn = True

    assert found_spawn, "Hook must spawn the interactive monitor using pexpect.spawn"
    assert MONITOR_PATH in source, "Hook does not reference the required legacy monitor"


def test_successful_push():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    with tempfile.TemporaryDirectory() as tmpdir:
        run_cmd("git init", cwd=tmpdir)
        run_cmd("git config user.email 'test@example.com'", cwd=tmpdir)
        run_cmd("git config user.name 'Test User'", cwd=tmpdir)

        targets_path = os.path.join(tmpdir, "deploy_targets.txt")
        with open(targets_path, "w") as f:
            f.write("web-frontend\ndb-primary\n")

        run_cmd("git add deploy_targets.txt", cwd=tmpdir)
        run_cmd("git commit -m 'Add healthy targets'", cwd=tmpdir)
        run_cmd(f"git remote add origin {REPO_PATH}", cwd=tmpdir)
        res = run_cmd("git push origin master", cwd=tmpdir)

        assert res.returncode == 0, f"Expected push to succeed, but it failed. Stderr: {res.stderr}"
        assert "[OK] All services healthy." in res.stdout or "[OK] All services healthy." in res.stderr, "Success message not found in output"

        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} not created"
        with open(LOG_PATH, "r") as f:
            lines = f.read().strip().split('\n')
            last_line = lines[-1]
            try:
                log_entry = json.loads(last_line)
            except json.JSONDecodeError:
                pytest.fail(f"Last line of log file is not valid JSON: {last_line}")

            assert log_entry.get("status") == "accepted", f"Expected status 'accepted', got {log_entry.get('status')}"
            assert log_entry.get("failed_services") == [], "Expected empty failed_services list"
            assert "refs/heads/master" in log_entry.get("ref", ""), "Ref does not match expected master branch ref"


def test_rejected_push():
    with tempfile.TemporaryDirectory() as tmpdir:
        run_cmd("git init", cwd=tmpdir)
        run_cmd("git config user.email 'test@example.com'", cwd=tmpdir)
        run_cmd("git config user.name 'Test User'", cwd=tmpdir)

        targets_path = os.path.join(tmpdir, "deploy_targets.txt")
        with open(targets_path, "w") as f:
            f.write("auth-service\npayment-gateway\nmissing-service\n")

        run_cmd("git add deploy_targets.txt", cwd=tmpdir)
        run_cmd("git commit -m 'Add failing targets'", cwd=tmpdir)
        run_cmd(f"git remote add origin {REPO_PATH}", cwd=tmpdir)
        res = run_cmd("git push origin master", cwd=tmpdir)

        assert res.returncode != 0, "Expected push to fail, but it succeeded."
        assert "[ALERT] Service payment-gateway is down or unknown!" in res.stderr, "Alert for payment-gateway missing in stderr"
        assert "[ALERT] Service missing-service is down or unknown!" in res.stderr, "Alert for missing-service missing in stderr"

        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} not found"
        with open(LOG_PATH, "r") as f:
            lines = f.read().strip().split('\n')
            last_line = lines[-1]
            try:
                log_entry = json.loads(last_line)
            except json.JSONDecodeError:
                pytest.fail(f"Last line of log file is not valid JSON: {last_line}")

            assert log_entry.get("status") == "rejected", f"Expected status 'rejected', got {log_entry.get('status')}"
            failed_services = log_entry.get("failed_services", [])
            assert "payment-gateway" in failed_services, "payment-gateway missing from failed_services"
            assert "missing-service" in failed_services, "missing-service missing from failed_services"
            assert "refs/heads/master" in log_entry.get("ref", ""), "Ref does not match expected master branch ref"


def git_object(args, input_text=None):
    env = os.environ.copy()
    env.update({
        "GIT_AUTHOR_NAME": "Verifier",
        "GIT_AUTHOR_EMAIL": "verifier@example.com",
        "GIT_COMMITTER_NAME": "Verifier",
        "GIT_COMMITTER_EMAIL": "verifier@example.com",
    })
    res = subprocess.run(
        ["git", "--git-dir", REPO_PATH] + args,
        input=input_text,
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    assert res.returncode == 0, res.stderr
    return res.stdout.strip()


def make_commit(target_text):
    blob = git_object(["hash-object", "-w", "--stdin"], target_text)
    tree = git_object(["mktree"], f"100644 blob {blob}\tdeploy_targets.txt\n")
    return git_object(["commit-tree", tree, "-m", "dynamic verifier input"])


def read_events(trace_path):
    with open(trace_path, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def run_dynamic_case(services, statuses, expected_failed, refname, trace_path):
    if os.path.exists(trace_path):
        os.remove(trace_path)
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    target_text = "\n".join(
        ([services[0], ""] + services[1:])
    ) + "\n\n"
    commit = make_commit(target_text)
    env = os.environ.copy()
    env["GIT_DIR"] = REPO_PATH
    res = subprocess.run(
        [HOOK_PATH],
        input=f"{'0' * 40} {commit} {refname}\n",
        text=True,
        capture_output=True,
        cwd=REPO_PATH,
        env=env,
        timeout=15,
    )

    if expected_failed:
        assert res.returncode != 0, "Hook accepted dynamically generated unhealthy services"
        expected_alerts = [f"[ALERT] Service {svc} is down or unknown!" for svc in expected_failed]
        assert res.stderr.strip().splitlines() == expected_alerts
    else:
        assert res.returncode == 0, f"Hook rejected dynamically generated healthy services: {res.stderr}"
        assert res.stdout.strip().splitlines() == ["[OK] All services healthy."]
        assert res.stderr == ""

    assert os.path.isfile(LOG_PATH), "Hook did not create the monitoring log"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        log_lines = [line for line in f if line.strip()]
    assert len(log_lines) == 1, "A hook invocation must append exactly one JSON log object"
    assert json.loads(log_lines[0]) == {
        "ref": refname,
        "status": "rejected" if expected_failed else "accepted",
        "failed_services": expected_failed,
    }

    events = read_events(trace_path)
    starts = [e for e in events if e["event"] == "start"]
    checked = [e["service"] for e in events if e["event"] == "service"]
    answers = [e["answer"] for e in events if e["event"] == "answer"]
    exits = [e for e in events if e["event"] == "exit"]

    assert len(starts) == 1, "All services must be checked in one spawned monitor session"
    assert starts[0]["stdin_tty"] and starts[0]["stdout_tty"], "Monitor was not driven through a pexpect-style pseudo-terminal"
    assert checked == services, "Hook did not check every non-empty target sequentially"
    assert answers == (["y"] * (len(services) - 1) + ["n"]), "Hook did not correctly continue and terminate the single monitor session"
    assert len(exits) == 1, "Hook did not cleanly terminate the monitor"


def test_randomized_services_use_one_real_interactive_session():
    original = open(MONITOR_PATH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(MONITOR_PATH).st_mode)

    with tempfile.TemporaryDirectory() as work:
        config_path = os.path.join(work, "statuses.json")
        trace_path = os.path.join(work, "trace.jsonl")
        monitor_source = '''import json
import os
import sys

CONFIG = %r
TRACE = %r

def record(obj):
    with open(TRACE, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj) + "\\n")

def main():
    with open(CONFIG, "r", encoding="utf-8") as f:
        statuses = json.load(f)
    record({"event": "start", "pid": os.getpid(), "stdin_tty": sys.stdin.isatty(), "stdout_tty": sys.stdout.isatty()})
    while True:
        sys.stdout.write("Enter service name: ")
        sys.stdout.flush()
        service = sys.stdin.readline().strip()
        if not service:
            return
        record({"event": "service", "service": service})
        print("Status: " + statuses.get(service, "UNKNOWN"), flush=True)
        sys.stdout.write("Check another? (y/n): ")
        sys.stdout.flush()
        answer = sys.stdin.readline().strip().lower()
        record({"event": "answer", "answer": answer})
        if answer != "y":
            record({"event": "exit"})
            return

if __name__ == "__main__":
    main()
''' % (config_path, trace_path)

        try:
            with open(MONITOR_PATH, "w", encoding="utf-8") as f:
                f.write(monitor_source)
            os.chmod(MONITOR_PATH, 0o755)

            token = secrets.token_hex(8)
            healthy = [f"healthy-{token}-{i}" for i in range(4)]
            healthy_statuses = {svc: "OK" for svc in healthy}
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(healthy_statuses, f)
            run_dynamic_case(
                healthy,
                healthy_statuses,
                [],
                f"refs/heads/healthy-{token}",
                trace_path,
            )

            mixed = [f"mixed-{token}-{i}" for i in range(5)]
            mixed_statuses = {
                mixed[0]: "OK",
                mixed[1]: "DOWN",
                mixed[2]: "OK",
                mixed[3]: "UNKNOWN",
                mixed[4]: "OK",
            }
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(mixed_statuses, f)
            run_dynamic_case(
                mixed,
                mixed_statuses,
                [mixed[1], mixed[3]],
                f"refs/heads/mixed-{token}",
                trace_path,
            )
        finally:
            with open(MONITOR_PATH, "wb") as f:
                f.write(original)
            os.chmod(MONITOR_PATH, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
