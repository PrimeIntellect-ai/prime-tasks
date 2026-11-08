#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import subprocess
import tempfile
import time


def test_deploy_edge_script():
    script_path = '/home/user/deploy_edge.sh'
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, 'r') as f:
        content = f.read()

    # Preserve the original static assertions.
    assert 'qemu-system-x86_64' in content, "deploy_edge.sh is missing 'qemu-system-x86_64'."
    assert re.search(r'-m\s+512\b', content), "deploy_edge.sh is missing '-m 512'."
    assert '-nographic' in content, "deploy_edge.sh is missing '-nographic'."
    assert re.search(r'hostfwd=[a-zA-Z0-9:]*8080-[a-zA-Z0-9:]*80\b', content) or \
           re.search(r'hostfwd=[a-zA-Z0-9:]*8080::80\b', content) or \
           '8080-:80' in content or '8080::80' in content, \
           "deploy_edge.sh is missing correct hostfwd mapping for port 8080 to 80."
    assert re.search(r'hostfwd=[a-zA-Z0-9:]*5901-[a-zA-Z0-9:]*5900\b', content) or \
           re.search(r'hostfwd=[a-zA-Z0-9:]*5901::5900\b', content) or \
           '5901-:5900' in content or '5901::5900' in content, \
           "deploy_edge.sh is missing correct hostfwd mapping for port 5901 to 5900."
    assert '/home/user/images/edge_device.img' in content, "deploy_edge.sh does not target the correct image path."

    # Execute the deployment script with a harmless QEMU shim and inspect the
    # arguments that would actually be supplied to QEMU.
    with tempfile.TemporaryDirectory() as td:
        capture = os.path.join(td, 'calls.jsonl')
        pids = os.path.join(td, 'pids')
        shim = os.path.join(td, 'qemu-system-x86_64')
        with open(shim, 'w') as f:
            f.write('''#!/usr/bin/python3
import json, os, sys, time
with open(os.environ["QEMU_CAPTURE"], "a") as out:
    out.write(json.dumps(sys.argv[1:]) + "\\n")
with open(os.environ["QEMU_PIDS"], "a") as out:
    out.write(str(os.getpid()) + "\\n")
# A foreground launch remains alive long enough for the verifier to distinguish
# it from -daemonize or shell-level detached execution.
if "-daemonize" not in sys.argv[1:] and "--version" not in sys.argv[1:] and "-version" not in sys.argv[1:]:
    time.sleep(4)
''')
        os.chmod(shim, 0o755)
        env = os.environ.copy()
        env['PATH'] = td + os.pathsep + env.get('PATH', '')
        env['QEMU_CAPTURE'] = capture
        env['QEMU_PIDS'] = pids

        start = time.monotonic()
        try:
            result = subprocess.run([script_path], env=env, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    timeout=7)
            elapsed = time.monotonic() - start
            assert result.returncode == 0, f"deploy_edge.sh exited with status {result.returncode}."
            assert elapsed < 2.5, "QEMU was launched in the foreground rather than detached."

            deadline = time.monotonic() + 1.0
            while not os.path.exists(capture) and time.monotonic() < deadline:
                time.sleep(0.02)
            assert os.path.isfile(capture), "deploy_edge.sh did not execute qemu-system-x86_64."

            with open(capture) as f:
                calls = [json.loads(line) for line in f if line.strip()]
            launches = [a for a in calls if '/home/user/images/edge_device.img' in ' '.join(a)]
            assert launches, "No executed QEMU command used the required disk image."
            args = launches[-1]
            joined = ' '.join(args)

            assert '-nographic' in args, "Executed QEMU command is missing -nographic."
            assert any('/home/user/images/edge_device.img' in a for a in args), \
                "Executed QEMU command does not use the required image."

            memory = None
            for i, arg in enumerate(args):
                if arg == '-m' and i + 1 < len(args):
                    memory = args[i + 1]
                    break
                if arg.startswith('-m='):
                    memory = arg.split('=', 1)[1]
                    break
            assert memory is not None and re.fullmatch(r'512(?:[mM])?', memory), \
                f"Executed QEMU command does not allocate exactly 512 MB: {args}"

            assert any(a == 'user' or a.startswith('user,') for a in args), \
                "Executed QEMU command does not configure user-mode networking."
            fwd_8080 = re.search(r'hostfwd=tcp:(?:[^,:]*):8080-(?:[^,:]*):80(?=,|\s|$)', joined)
            fwd_5901 = re.search(r'hostfwd=tcp:(?:[^,:]*):5901-(?:[^,:]*):5900(?=,|\s|$)', joined)
            assert fwd_8080, f"Executed QEMU command lacks host TCP 8080 to guest 80 forwarding: {args}"
            assert fwd_5901, f"Executed QEMU command lacks host TCP 5901 to guest 5900 forwarding: {args}"
            assert '-daemonize' in args or elapsed < 2.5, \
                "Executed QEMU command is neither daemonized nor otherwise detached."
        finally:
            if os.path.exists(pids):
                with open(pids) as f:
                    for line in f:
                        try:
                            os.kill(int(line.strip()), signal.SIGKILL)
                        except (ValueError, ProcessLookupError, PermissionError):
                            pass


def _set_image_size(path, size):
    with open(path, 'r+b') as f:
        f.truncate(size)
    os.chown(path, 1000, 1000)


def _run_quota(script):
    result = subprocess.run(['runuser', '-u', 'user', '--', script],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, \
        f"check_quota.sh failed as user: stdout={result.stdout!r}, stderr={result.stderr!r}"


def test_check_quota_script():
    script_path = '/home/user/check_quota.sh'
    img_path = '/home/user/images/edge_device.img'
    log_path = '/home/user/alerts.log'
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    rng = random.SystemRandom()
    above_sizes = [105 * 1024 * 1024,
                   104857600 + rng.randint(1, 7 * 1024 * 1024)]
    at_or_below_sizes = [50 * 1024 * 1024, 104857600,
                         rng.randint(1, 104857599)]

    # Each over-limit run must append exactly the alert derived from the actual
    # current file size; pre-populated fixed alerts cannot satisfy this check.
    for size in above_sizes:
        with open(log_path, 'wb') as f:
            f.write(b'BASELINE\n')
        os.chown(log_path, 1000, 1000)
        _set_image_size(img_path, size)
        _run_quota(script_path)
        with open(log_path, 'rb') as f:
            actual = f.read()
        expected = f"BASELINE\nALERT: Storage limit exceeded - {size} bytes".encode()
        assert actual in (expected, expected + b'\n'), \
            f"Expected exactly one alert for actual size {size}; got {actual!r}."

    # At and below the threshold, the existing log must remain byte-for-byte unchanged.
    for size in at_or_below_sizes:
        baseline = b'UNCHANGED SENTINEL\n'
        with open(log_path, 'wb') as f:
            f.write(baseline)
        os.chown(log_path, 1000, 1000)
        _set_image_size(img_path, size)
        _run_quota(script_path)
        with open(log_path, 'rb') as f:
            assert f.read() == baseline, \
                f"Script incorrectly changed alerts.log for size {size}."


def test_cron_backup_and_active_crontab():
    backup_path = '/home/user/cron_backup.txt'
    assert os.path.isfile(backup_path), f"{backup_path} does not exist."
    with open(backup_path, 'r') as f:
        backup = f.read()

    # Preserve the original backup assertions.
    has_schedule = re.search(r'(?:\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*', backup)
    has_script = '/home/user/check_quota.sh' in backup
    assert has_schedule and has_script, \
        f"cron_backup.txt does not contain the correct 15-minute schedule for check_quota.sh. Found: {backup}"

    result = subprocess.run(['crontab', '-u', 'user', '-l'], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"User's active crontab is missing: {result.stderr}"
    active = result.stdout
    assert backup.strip() == active.strip(), \
        "cron_backup.txt is not a dump of the active user crontab."

    matching_jobs = []
    wrong_schedule_jobs = []
    for raw in active.splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split(None, 5)
        if len(parts) < 6:
            continue
        schedule = parts[:5]
        command = parts[5]
        if '/home/user/check_quota.sh' in command:
            if schedule in (["*/15", "*", "*", "*", "*"],
                            ["0,15,30,45", "*", "*", "*", "*"]):
                matching_jobs.append(line)
            else:
                wrong_schedule_jobs.append(line)

    assert matching_jobs, "The active user crontab lacks the required every-15-minutes job."
    assert not wrong_schedule_jobs, \
        f"check_quota.sh is also scheduled at an incorrect frequency: {wrong_schedule_jobs}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
