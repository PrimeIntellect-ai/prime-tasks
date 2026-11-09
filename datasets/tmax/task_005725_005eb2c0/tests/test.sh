#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import time


def test_nginx_conf_fixed():
    conf_path = "/home/user/finops-scale/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing."
    with open(conf_path, "r") as f:
        content = f.read()

    expected_path = "proxy_pass http://unix:/home/user/finops-scale/sockets/app.sock;"
    assert expected_path in content, (
        "nginx.conf does not contain the correct proxy_pass directive. "
        f"Expected it to contain: {expected_path}"
    )

    # Inspect active directives, rather than accepting the correct text in a
    # comment or appended alongside the original broken directive.
    active_content = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    proxy_pass_values = [value.strip() for value in re.findall(
        r"\bproxy_pass\s+([^;]+);", active_content
    )]
    expected_value = "http://unix:/home/user/finops-scale/sockets/app.sock"
    assert proxy_pass_values == [expected_value], (
        "nginx.conf must contain exactly one active proxy_pass directive, "
        f"set to {expected_value}; found {proxy_pass_values}."
    )


def test_finops_users_created():
    users_path = "/home/user/finops-scale/finops-users.txt"
    assert os.path.isfile(users_path), f"File {users_path} is missing."
    with open(users_path, "r") as f:
        content = f.read().strip()
    expected_line = "cost-saver:finops-admin:active"
    assert content == expected_line, (
        f"finops-users.txt content is incorrect. Expected '{expected_line}', "
        f"got '{content}'."
    )


def test_worker_fstab_created():
    fstab_path = "/home/user/finops-scale/worker-fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} is missing."
    with open(fstab_path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.startswith("#")]

    assert len(lines) == 1, "worker-fstab should contain exactly one non-comment line."
    parts = lines[0].split()
    assert len(parts) == 6, f"worker-fstab entry should have exactly 6 fields, found {len(parts)}."
    assert parts[0] == "/home/user/data-disk.img", f"Incorrect device/file path: {parts[0]}"
    assert parts[1] == "/home/user/finops-scale/shared_data", f"Incorrect mount point: {parts[1]}"
    assert parts[2] == "ext4", f"Incorrect filesystem type: {parts[2]}"
    assert parts[3] == "loop,ro", f"Incorrect mount options: {parts[3]}"
    assert parts[4] == "0", f"Incorrect dump field: {parts[4]}"
    assert parts[5] == "0", f"Incorrect pass field: {parts[5]}"


def test_scaler_script_behavior():
    script_path = "/home/user/finops-scale/scaler.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"{script_path} is not executable."

    log_path = "/home/user/finops-scale/metrics.log"
    worker_path = "/home/user/finops-scale/mock-worker.py"
    assert os.path.isfile(worker_path), f"Worker script {worker_path} missing."

    trusted_worker = b"import time\nwhile True:\n    time.sleep(1)\n"
    with open(worker_path, "rb") as f:
        actual_worker = f.read()
    assert actual_worker == trusted_worker, "mock-worker.py fixture was modified."

    processes = []

    def restore_worker():
        # Prevent a scaler invocation from changing the fixture used by a later case.
        with open(worker_path, "wb") as f:
            f.write(trusted_worker)

    def start_worker():
        restore_worker()
        proc = subprocess.Popen(["python3", worker_path])
        processes.append(proc)
        time.sleep(0.35)
        assert proc.poll() is None, "Trusted mock worker failed to remain running."
        return proc

    def run_scaler(context):
        result = subprocess.run(
            [script_path], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, (
            f"scaler.sh exited with non-zero status when {context}. "
            f"stderr: {result.stderr}"
        )

    try:
        # BUSY and unpredictable non-IDLE last lines must leave workers untouched.
        non_idle_logs = [
            "STATUS:BUSY\n",
            f"STATUS:{secrets.token_hex(16)}\n",
            f"arbitrary-{secrets.token_hex(20)}\n",
            f"STATUS:IDLE\nSTATUS:{secrets.token_hex(16)}\n",
        ]
        for log_content in non_idle_logs:
            with open(log_path, "w") as f:
                f.write(log_content)
            proc = start_worker()
            run_scaler(f"the last log line was {log_content.splitlines()[-1]!r}")
            time.sleep(0.35)
            assert proc.poll() is None, (
                "scaler.sh improperly terminated a worker for a non-IDLE last line."
            )
            proc.terminate()
            proc.wait(timeout=3)

        # IDLE must terminate every matching worker, specifically with SIGTERM.
        with open(log_path, "w") as f:
            f.write(f"previous-{secrets.token_hex(8)}\nSTATUS:IDLE\n")
        idle_workers = [start_worker(), start_worker()]
        run_scaler("the last log line was STATUS:IDLE")
        for proc in idle_workers:
            proc.wait(timeout=3)
            assert proc.returncode == -15, (
                "scaler.sh must gracefully terminate every matching worker with SIGTERM."
            )
    finally:
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        restore_worker()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
