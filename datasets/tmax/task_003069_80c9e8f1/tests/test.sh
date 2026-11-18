#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
from pathlib import Path


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_mail_env_sh():
    """Verify /home/user/mail_env.sh exists and exports the correct variables."""
    path = "/home/user/mail_env.sh"
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "MAILING_DOMAIN=system-deploy.local" in content, "MAILING_DOMAIN not exported correctly."
    assert "DEPLOY_WORKERS=3" in content, "DEPLOY_WORKERS not exported correctly."
    assert "ROLLOUT_DELAY_MS=100" in content, "ROLLOUT_DELAY_MS not exported correctly."

    result = subprocess.run(
        ["/bin/bash", "-c", "source /home/user/mail_env.sh && printf '%s\\n%s\\n%s\\n' \"$MAILING_DOMAIN\" \"$DEPLOY_WORKERS\" \"$ROLLOUT_DELAY_MS\""],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["system-deploy.local", "3", "100"]


def test_mail_worker_sh():
    """Verify /home/user/mail_worker.sh exists and is executable."""
    path = "/home/user/mail_worker.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_postfix_mock_cf():
    """Verify /home/user/postfix_mock.cf exists and has exact content."""
    path = "/home/user/postfix_mock.cf"
    assert os.path.isfile(path), f"{path} does not exist."
    expected = [
        "primary_domain = system-deploy.local",
        "active_daemons = 3",
    ]
    assert nonempty_lines(path) == expected, f"Content of {path} does not match expected."


def test_worker_events_log():
    """Verify /home/user/worker_events.log exists and has exact content."""
    path = "/home/user/worker_events.log"
    assert os.path.isfile(path), f"{path} does not exist."
    expected = [
        "[INIT] Worker 1 listening for system-deploy.local",
        "[INIT] Worker 2 listening for system-deploy.local",
        "[INIT] Worker 3 listening for system-deploy.local",
    ]
    assert nonempty_lines(path) == expected, f"Content of {path} does not match expected."


def test_deployd_log():
    """Verify /home/user/deployd.log exists and has exact content."""
    path = "/home/user/deployd.log"
    assert os.path.isfile(path), f"{path} does not exist."
    expected = [
        "Staged rollout complete for worker 1",
        "Staged rollout complete for worker 2",
        "Staged rollout complete for worker 3",
    ]
    assert nonempty_lines(path) == expected, f"Content of {path} does not match expected."


def test_deployd_binary():
    """Verify the Rust binary was compiled and exists at the correct path."""
    path = "/home/user/deployd/target/release/deployd"
    assert os.path.isfile(path), f"Rust binary {path} does not exist. Did you compile with --release?"
    assert os.access(path, os.X_OK), f"Rust binary {path} is not executable."


def test_functional_execution():
    project = Path("/home/user/deployd")
    worker = Path("/home/user/mail_worker.sh")
    events = Path("/home/user/worker_events.log")
    deploy_log = Path("/home/user/deployd.log")
    config = Path("/home/user/postfix_mock.cf")
    probe_log = Path("/tmp/deployd_worker_probe.log")

    assert (project / "Cargo.toml").is_file(), "Rust project is missing Cargo.toml"
    assert (project / "src/main.rs").is_file(), "Rust project is missing src/main.rs"

    build = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=str(project),
        text=True,
        capture_output=True,
        timeout=120,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"

    binary = project / "target/release/deployd"
    assert binary.is_file() and os.access(binary, os.X_OK)
    with open(binary, "rb") as f:
        assert f.read(4) == b"\\x7fELF", "deployd is not the compiled native binary"

    # Exercise the submitted worker itself with a derived environment value and
    # verify that invalid argument counts are rejected.
    events.unlink(missing_ok=True)
    worker_env = os.environ.copy()
    worker_env["MAILING_DOMAIN"] = "verifier-runtime.invalid"
    valid = subprocess.run([str(worker), "17"], env=worker_env, timeout=5)
    assert valid.returncode == 0
    assert nonempty_lines(events) == ["[INIT] Worker 17 listening for verifier-runtime.invalid"]

    events.unlink(missing_ok=True)
    no_arg = subprocess.run([str(worker)], env=worker_env, timeout=5)
    two_args = subprocess.run([str(worker), "1", "2"], env=worker_env, timeout=5)
    assert no_arg.returncode != 0, "mail_worker.sh must require exactly one argument"
    assert two_args.returncode != 0, "mail_worker.sh must require exactly one argument"
    assert not events.exists() or nonempty_lines(events) == [], "invalid worker invocations must not log an initialization"

    original_worker = worker.read_bytes()
    original_mode = stat.S_IMODE(worker.stat().st_mode)
    probe = r'''#!/bin/bash
if [ "$#" -ne 1 ]; then exit 64; fi
id="$1"
case "$id" in 1|2|3) ;; *) exit 65 ;; esac
if [ "$id" -gt 1 ] && [ ! -f "/tmp/deployd_probe_done_$((id-1))" ]; then exit 66; fi
python3 - "$id" <<'PY'
import sys, time
with open('/tmp/deployd_worker_probe.log', 'a') as f:
    f.write('start %s %d\n' % (sys.argv[1], time.monotonic_ns()))
PY
printf '[INIT] Worker %s listening for %s\n' "$id" "$MAILING_DOMAIN" >> /home/user/worker_events.log
sleep 0.03
python3 - "$id" <<'PY'
import sys, time
with open('/tmp/deployd_worker_probe.log', 'a') as f:
    f.write('finish %s %d\n' % (sys.argv[1], time.monotonic_ns()))
PY
touch "/tmp/deployd_probe_done_$id"
exit 0
'''

    try:
        worker.write_text(probe)
        worker.chmod(0o755)
        for path in (events, deploy_log, config, probe_log):
            path.unlink(missing_ok=True)
        for i in range(1, 4):
            Path(f"/tmp/deployd_probe_done_{i}").unlink(missing_ok=True)

        run_env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "HOME": "/home/user",
            "MAILING_DOMAIN": "system-deploy.local",
            "DEPLOY_WORKERS": "3",
            "ROLLOUT_DELAY_MS": "100",
        }
        result = subprocess.run([str(binary)], env=run_env, text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, f"deployd execution failed:\n{result.stdout}\n{result.stderr}"

        assert nonempty_lines(config) == [
            "primary_domain = system-deploy.local",
            "active_daemons = 3",
        ]
        assert nonempty_lines(events) == [
            "[INIT] Worker 1 listening for system-deploy.local",
            "[INIT] Worker 2 listening for system-deploy.local",
            "[INIT] Worker 3 listening for system-deploy.local",
        ]
        assert nonempty_lines(deploy_log) == [
            "Staged rollout complete for worker 1",
            "Staged rollout complete for worker 2",
            "Staged rollout complete for worker 3",
        ]

        records = [line.split() for line in probe_log.read_text().splitlines() if line.strip()]
        assert [(r[0], r[1]) for r in records] == [
            ("start", "1"), ("finish", "1"),
            ("start", "2"), ("finish", "2"),
            ("start", "3"), ("finish", "3"),
        ], "deployd did not spawn and wait for workers sequentially"
        times = {(kind, wid): int(ns) for kind, wid, ns in records}
        assert times[("start", "2")] - times[("finish", "1")] >= 70_000_000, "missing rollout sleep before worker 2"
        assert times[("start", "3")] - times[("finish", "2")] >= 70_000_000, "missing rollout sleep before worker 3"
    finally:
        worker.write_bytes(original_worker)
        worker.chmod(original_mode)
        probe_log.unlink(missing_ok=True)
        for i in range(1, 4):
            Path(f"/tmp/deployd_probe_done_{i}").unlink(missing_ok=True)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
