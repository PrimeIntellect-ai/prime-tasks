#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
import time


def derive_expected_values():
    usage = {}
    with open('/home/user/net_usage.csv', newline='') as f:
        for row in csv.reader(f):
            if not row or row[0] == 'User':
                continue
            assert len(row) == 4, f'Invalid row in net_usage.csv: {row}'
            usage[row[0]] = int(row[2]) + int(row[3])

    totals = {}
    with open('/home/user/groups.db') as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            group, members = raw.split(':', 1)
            totals[group] = sum(usage[user] for user in members.split(',') if user)

    assert totals, 'No groups were found'
    top_group, total = max(totals.items(), key=lambda item: item[1])
    return top_group, total * 80 // 100


def test_quota_updated_log():
    path = "/home/user/quota_updated.log"
    assert os.path.isfile(path), f"File {path} is missing. The expect script may not have run successfully."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content == "ops:13600", f"Expected 'ops:13600' in {path}, but found '{content}'"


def test_expect_script_exists():
    path = "/home/user/update_quota.exp"
    assert os.path.isfile(path), f"File {path} is missing."


def test_configure_alerts_script_exists():
    path = "/home/user/configure_alerts.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_capacity_alerts_conf():
    path = "/home/user/capacity_alerts.conf"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines()]

    assert "ALERT_GROUP=ops" in lines, f"'ALERT_GROUP=ops' not found in {path}"
    assert "THRESHOLD=13600" in lines, f"'THRESHOLD=13600' not found in {path}"


def test_configure_alerts_idempotency():
    path = "/home/user/capacity_alerts.conf"
    script = "/home/user/configure_alerts.sh"

    result = subprocess.run([script], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script} failed on second run."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    alert_group_count = lines.count("ALERT_GROUP=ops")
    threshold_count = lines.count("THRESHOLD=13600")

    assert alert_group_count == 1, f"Idempotency failed: 'ALERT_GROUP=ops' appears {alert_group_count} times."
    assert threshold_count == 1, f"Idempotency failed: 'THRESHOLD=13600' appears {threshold_count} times."


def test_expect_script_actually_drives_quota_manager():
    expected_group, expected_quota = derive_expected_values()
    assert (expected_group, expected_quota) == ('ops', 13600)

    script = '/home/user/update_quota.exp'
    manager = '/home/user/quota_mgr'
    output = '/home/user/quota_updated.log'
    marker = '/tmp/quota_mgr_invoked'
    token = secrets.token_hex(16)

    with open(manager, 'w') as f:
        f.write(f'''#!/bin/bash\nprintf '%s\\n' '{token}' > '{marker}'\nread -p "Enter group to restrict: " GROUP\nread -p "Enter new bandwidth limit: " LIMIT\necho "${{GROUP}}:${{LIMIT}}" > '{output}'\necho "Quota updated successfully."\n''')
    os.chmod(manager, 0o755)

    for path in (output, marker):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ['/usr/bin/expect', script], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f'Expect script failed when executed. stdout={result.stdout!r}, '
        f'stderr={result.stderr!r}'
    )
    assert os.path.isfile(marker), 'The Expect script did not launch /home/user/quota_mgr.'
    with open(marker) as f:
        assert f.read().strip() == token
    assert os.path.isfile(output), 'Executing the Expect script did not apply a quota.'
    with open(output) as f:
        actual = f.read().strip()
    assert actual == f'{expected_group}:{expected_quota}', (
        f'Expect script supplied the wrong values: {actual!r}'
    )


def test_configure_alerts_updates_and_is_strictly_idempotent():
    expected_group, expected_quota = derive_expected_values()
    path = '/home/user/capacity_alerts.conf'
    script = '/home/user/configure_alerts.sh'
    unrelated = '# unrelated setting must remain\nEMAIL=alerts@example.test\n'

    with open(path, 'w') as f:
        f.write(unrelated)
        f.write('ALERT_GROUP=old_group\n')
        f.write('THRESHOLD=1\n')
        f.write('ALERT_GROUP=duplicate_old_group\n')

    first = subprocess.run([script], capture_output=True, text=True, timeout=10)
    assert first.returncode == 0, (
        f'Configuration script failed while updating stale values: {first.stderr!r}'
    )

    with open(path, 'rb') as f:
        first_bytes = f.read()
    text = first_bytes.decode()
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert '# unrelated setting must remain' in lines
    assert 'EMAIL=alerts@example.test' in lines
    assert lines.count(f'ALERT_GROUP={expected_group}') == 1
    assert lines.count(f'THRESHOLD={expected_quota}') == 1
    assert len([line for line in lines if line.startswith('ALERT_GROUP=')]) == 1
    assert len([line for line in lines if line.startswith('THRESHOLD=')]) == 1

    before = os.stat(path)
    time.sleep(1.1)
    second = subprocess.run([script], capture_output=True, text=True, timeout=10)
    assert second.returncode == 0, (
        f'Configuration script failed on an already-correct file: {second.stderr!r}'
    )
    after = os.stat(path)
    with open(path, 'rb') as f:
        second_bytes = f.read()

    assert second_bytes == first_bytes, 'A repeated run changed the correct config contents.'
    assert after.st_mtime_ns == before.st_mtime_ns, (
        'A repeated run modified the already-correct config file.'
    )
    assert after.st_ino == before.st_ino, (
        'A repeated run replaced the already-correct config file.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
