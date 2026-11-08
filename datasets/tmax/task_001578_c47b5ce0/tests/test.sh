#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import ast
import json
import os
import re
import secrets
import stat
import subprocess


def test_monitor_log():
    log_path = '/home/user/app_logs/monitor.log'
    assert os.path.exists(log_path), "monitor.log does not exist"

    with open(log_path, 'r') as f:
        lines = f.readlines()
        assert len(lines) >= 1, "Log file is empty"
        last_line = lines[-1].strip()
        try:
            data = json.loads(last_line)
        except json.JSONDecodeError:
            assert False, "Last line of monitor.log is not valid JSON"

        assert data.get("event") == "service_check", "event key missing or incorrect in monitor.log"
        assert data.get("status") == "FAILURE_DETECTED", "status key missing or incorrect in monitor.log"


def test_monitor_script_executes_legacy_service_with_pexpect():
    monitor_path = '/home/user/monitor.py'
    service_path = '/home/user/legacy_service.sh'
    log_path = '/home/user/app_logs/monitor.log'

    assert os.path.isfile(monitor_path), "monitor.py does not exist or is not a regular file"

    with open(monitor_path, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=monitor_path)
    except SyntaxError as exc:
        assert False, f"monitor.py is not valid Python: {exc}"

    pexpect_aliases = set()
    imported_spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'pexpect':
                    pexpect_aliases.add(alias.asname or 'pexpect')
        elif isinstance(node, ast.ImportFrom) and node.module == 'pexpect':
            for alias in node.names:
                if alias.name == 'spawn':
                    imported_spawn_aliases.add(alias.asname or 'spawn')

    assert pexpect_aliases or imported_spawn_aliases, "monitor.py must import pexpect"
    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if (node.func.attr == 'spawn' and isinstance(node.func.value, ast.Name)
                    and node.func.value.id in pexpect_aliases):
                uses_spawn = True
        elif isinstance(node.func, ast.Name) and node.func.id in imported_spawn_aliases:
            uses_spawn = True
    assert uses_spawn, "monitor.py must call pexpect.spawn"

    status_value = 'AUDIT_' + secrets.token_hex(12).upper()
    trace_path = '/tmp/legacy_service_trace_' + secrets.token_hex(12)
    with open(service_path, 'rb') as f:
        original_service = f.read()
    original_mode = stat.S_IMODE(os.stat(service_path).st_mode)

    replacement_path = service_path + '.verifier_tmp'
    replacement = f'''#!/bin/bash
printf 'Enter monitor password: '
IFS= read -r PASS
printf '%s' "$PASS" > '{trace_path}'
if [ "$PASS" = "alertadmin" ]; then
    echo 'STATUS: {status_value}'
else
    echo 'STATUS: UNAUTHORIZED'
fi
'''

    try:
        with open(replacement_path, 'w') as f:
            f.write(replacement)
        os.chmod(replacement_path, 0o755)
        os.replace(replacement_path, service_path)

        if os.path.exists(log_path):
            os.remove(log_path)

        result = subprocess.run(
            ['runuser', '-u', 'user', '--', 'python3', monitor_path],
            cwd='/home/user',
            env={**os.environ, 'HOME': '/home/user'},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"monitor.py failed when executed: stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert os.path.exists(trace_path), "monitor.py did not launch /home/user/legacy_service.sh"
        with open(trace_path, 'r') as f:
            supplied_password = f.read()
        assert supplied_password == 'alertadmin', "monitor.py did not send the required password"

        assert os.path.isfile(log_path), "monitor.py did not generate monitor.log"
        with open(log_path, 'r') as f:
            lines = f.read().splitlines()
        assert len(lines) == 1, "A fresh monitor run must append exactly one JSON line"
        try:
            data = json.loads(lines[0])
        except json.JSONDecodeError:
            assert False, "monitor.py did not write valid JSON"
        assert set(data.keys()) == {'event', 'status'}, "JSON line must contain exactly event and status"
        assert data['event'] == 'service_check', "monitor.py wrote an incorrect event"
        assert data['status'] == status_value, "monitor.py did not parse the service's runtime status"
    finally:
        try:
            with open(replacement_path, 'wb') as f:
                f.write(original_service)
            os.chmod(replacement_path, original_mode)
            os.replace(replacement_path, service_path)
        finally:
            if os.path.exists(trace_path):
                os.remove(trace_path)


def test_logrotate_config():
    config_path = '/home/user/monitor_logrotate.conf'
    assert os.path.exists(config_path), "monitor_logrotate.conf does not exist"

    with open(config_path, 'r') as f:
        content = f.read()

    assert re.search(r'\bsize\s+10k\b', content), "Missing or incorrect 'size 10k' directive in logrotate config"
    assert re.search(r'\brotate\s+4\b', content), "Missing or incorrect 'rotate 4' directive in logrotate config"
    assert re.search(r'\bcompress\b', content), "Missing 'compress' directive in logrotate config"
    assert re.search(r'\bcreate\s+0644\b', content), "Missing or incorrect 'create 0644' directive in logrotate config"
    assert re.search(r'\bmissingok\b', content), "Missing 'missingok' directive in logrotate config"
    assert re.search(r'\bnotifempty\b', content), "Missing 'notifempty' directive in logrotate config"


def test_backup_fstab():
    fstab_path = '/home/user/backup.fstab'
    assert os.path.exists(fstab_path), "backup.fstab does not exist"

    with open(fstab_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip() and not line.strip().startswith('#')]

    assert len(lines) == 1, "backup.fstab must contain exactly ONE active line"

    parts = re.split(r'\s+', lines[0])
    assert len(parts) >= 6, "fstab line does not have enough fields"

    assert parts[0] == "10.50.0.5:/export/backups", f"Incorrect remote source: {parts[0]}"
    assert parts[1] == "/home/user/remote_backups", f"Incorrect mount point: {parts[1]}"
    assert parts[2] == "nfs", f"Incorrect filesystem type: {parts[2]}"
    assert parts[3] == "ro,user,noauto,hard", f"Incorrect options: {parts[3]}"
    assert parts[4] == "0", f"Incorrect dump value: {parts[4]}"
    assert parts[5] == "0", f"Incorrect pass value: {parts[5]}"


def test_port_forward_sh():
    fw_path = '/home/user/port_forward.sh'
    assert os.path.exists(fw_path), "port_forward.sh does not exist"

    with open(fw_path, 'r') as f:
        content = f.read()

    # Check for required parts of the iptables command
    assert re.search(r'iptables\s+-t\s+nat\s+-[AI]\s+PREROUTING\s+-i\s+eth1\s+-p\s+tcp\s+--dport\s+80\s+-j\s+DNAT\s+--to-destination\s+192\.168\.1\.100:8080', content), "port_forward.sh does not contain the exact required iptables command"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
