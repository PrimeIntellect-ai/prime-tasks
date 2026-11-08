#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

SCRIPT_PATH = "/home/user/monitor/check_network.py"
BACKUP_PATH = "/home/user/backup/check_network.py.bak"
STATE_PATH = "/home/user/monitor/ss_output.txt"
LOG_PATH = "/home/user/monitor/logs/alert.log"

ORIGINAL_SCRIPT = b'''#!/usr/bin/env python3
import os
import subprocess

# Broken path
log_file = "./alert.log"

# TODO: Add grep/awk processing of /home/user/monitor/ss_output.txt
# TODO: Add timezone aware timestamp
# TODO: Write to absolute path and set permissions
'''


def test_backup_file():
    assert os.path.isfile(BACKUP_PATH), f"Backup file {BACKUP_PATH} does not exist."

    st = os.stat(BACKUP_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Backup file permissions should be 0400, but got {oct(perms)}."

    with open(BACKUP_PATH, "rb") as f:
        content = f.read()
    assert content == ORIGINAL_SCRIPT, "The backup is not an exact copy of the original script."


def test_alert_log():
    assert os.path.isfile(LOG_PATH), f"Alert log {LOG_PATH} does not exist. Did you run the script?"

    st = os.stat(LOG_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o444, f"Alert log permissions should be 0444, but got {oct(perms)}."

    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    pattern = r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ALERT: Port 8080 is bound by process "?nginx"?$'
    assert re.match(pattern, content), (
        f"Alert log content does not match the expected format.\n"
        f"Expected pattern: {pattern}\n"
        f"Actual content: {content}"
    )


def test_script_content():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "subprocess" in content, "The script must use 'subprocess' to execute grep/awk."
    assert "grep" in content, "The script must use 'grep' in the subprocess call."
    assert "awk" in content, "The script must use 'awk' in the subprocess call."
    assert LOG_PATH in content, "The script must use the absolute path for the alert log."


def test_script_execution_and_timezone():
    process_name = "auditproc7319"
    replacement_state = f'''State    Recv-Q    Send-Q       Local Address:Port       Peer Address:Port    Process
LISTEN   0         4096         127.0.0.1:6379           0.0.0.0:*            users:(("redis-server",pid=112,fd=4))
LISTEN   0         4096         0.0.0.0:8080             0.0.0.0:*            users:(("{process_name}",pid=555,fd=6))
LISTEN   0         4096         0.0.0.0:22               0.0.0.0:*            users:(("sshd",pid=99,fd=3))
'''

    hook_dir = "/tmp/verifier_subprocess_hook"
    trace_path = "/tmp/verifier_subprocess_trace.jsonl"
    os.makedirs(hook_dir, exist_ok=True)
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write('''import json\nimport subprocess\n_TRACE = "/tmp/verifier_subprocess_trace.jsonl"\n_original_popen = subprocess.Popen\ndef _recording_popen(*args, **kwargs):\n    command = kwargs.get("args", args[0] if args else None)\n    try:\n        with open(_TRACE, "a") as trace:\n            trace.write(json.dumps(command, default=str) + "\\n")\n    except Exception:\n        pass\n    return _original_popen(*args, **kwargs)\nsubprocess.Popen = _recording_popen\n''')

    with open(STATE_PATH, "rb") as f:
        original_state = f.read()

    try:
        with open(STATE_PATH, "w") as f:
            f.write(replacement_state)
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        if os.path.exists(trace_path):
            os.remove(trace_path)

        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        tokyo = ZoneInfo("Asia/Tokyo")
        before = datetime.now(tokyo) - timedelta(seconds=2)
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/tmp",
            env=env,
            text=True,
            capture_output=True,
            timeout=15,
        )
        after = datetime.now(tokyo) + timedelta(seconds=2)
        assert result.returncode == 0, (
            f"The script failed when executed from /tmp.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )

        assert os.path.isfile(LOG_PATH), "Executing the script did not create the alert log."
        perms = stat.S_IMODE(os.stat(LOG_PATH).st_mode)
        assert perms == 0o444, f"Executed script should set alert permissions to 0444, got {oct(perms)}."

        with open(LOG_PATH, "r") as f:
            content = f.read().strip()
        match = re.fullmatch(
            rf'\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})\] ALERT: Port 8080 is bound by process "?{re.escape(process_name)}"?',
            content,
        )
        assert match, f"Executed script produced an incorrect alert: {content!r}"

        timestamp = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=tokyo)
        assert before <= timestamp <= after, (
            f"Timestamp {match.group(1)} is not the current time in Asia/Tokyo."
        )

        assert os.path.isfile(trace_path), "No Python subprocess execution was observed."
        with open(trace_path, "r") as f:
            commands = [json.loads(line) for line in f if line.strip()]
        rendered = [json.dumps(command).lower() for command in commands]
        assert any("grep" in command for command in rendered), "The executed script did not run grep via subprocess."
        assert any("awk" in command for command in rendered), "The executed script did not run awk via subprocess."
        relevant = " ".join(rendered)
        assert STATE_PATH.lower() in relevant, "The subprocess pipeline did not reference ss_output.txt."
        assert "8080" in relevant, "The subprocess pipeline did not select port 8080."
    finally:
        with open(STATE_PATH, "wb") as f:
            f.write(original_state)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
