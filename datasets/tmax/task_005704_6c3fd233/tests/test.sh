#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import shutil
import stat
import subprocess
import tempfile
import time
import pytest

SCRIPT_PATH = "/home/user/monitor_script"


def test_monitor_script_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_crontab_entry():
    try:
        output = subprocess.check_output(['crontab', '-l'], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Has it been set up?")

    valid_cron_found = False
    candidate_commands = []
    for line in output.strip().split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '/home/user/monitor_script' in line:
            parts = line.split()
            if len(parts) >= 6:
                minute_field = parts[0]
                # Check for common valid 10-minute intervals
                if minute_field in ('*/10', '0,10,20,30,40,50'):
                    valid_cron_found = True
                    candidate_commands.append(' '.join(parts[5:]))

    assert valid_cron_found, "Could not find a valid crontab entry running /home/user/monitor_script every 10 minutes."

    # Verify that at least one matching cron command really executes the script,
    # rather than merely mentioning its path (for example, via echo).
    with open(SCRIPT_PATH, 'rb') as f:
        original = f.read()
    original_stat = os.stat(SCRIPT_PATH)
    marker = tempfile.mktemp(prefix='cron-monitor-marker-')
    try:
        with open(SCRIPT_PATH, 'w') as f:
            f.write('#!/bin/sh\nprintf cron-ran > "' + marker + '"\n')
        os.chmod(SCRIPT_PATH, 0o755)

        for command in candidate_commands:
            try:
                subprocess.run(['/bin/sh', '-c', command], timeout=10,
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
            except subprocess.TimeoutExpired:
                pass
            for _ in range(20):
                if os.path.exists(marker):
                    break
                time.sleep(0.05)
            if os.path.exists(marker):
                break

        assert os.path.exists(marker), "The matching cron entry does not actually execute /home/user/monitor_script."
    finally:
        with open(SCRIPT_PATH, 'wb') as f:
            f.write(original)
        os.chmod(SCRIPT_PATH, stat.S_IMODE(original_stat.st_mode))
        os.chown(SCRIPT_PATH, original_stat.st_uid, original_stat.st_gid)
        if os.path.exists(marker):
            os.unlink(marker)


def test_alert_log_contents():
    log_path = "/home/user/alert.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did the script run?"

    with open(log_path, "r") as f:
        log_content = f.read().splitlines()

    users_list_path = "/home/user/users_list.txt"
    quotas_path = "/home/user/quotas.json"

    assert os.path.isfile(users_list_path), f"{users_list_path} is missing."
    assert os.path.isfile(quotas_path), f"{quotas_path} is missing."

    with open(users_list_path, "r") as f:
        users = [line.strip() for line in f if line.strip()]

    with open(quotas_path, "r") as f:
        quotas = json.load(f)

    for user in users:
        # Get du -sb output
        du_cmd = ["du", "-sb", f"/home/user/data/users/{user}"]
        try:
            du_output = subprocess.check_output(du_cmd, text=True)
            usage_bytes = int(du_output.split()[0])
        except Exception as e:
            pytest.fail(f"Failed to calculate usage for {user}: {e}")

        quota = quotas.get(user)
        assert quota is not None, f"Quota for {user} not found."

        expected_log_line = f"ALERT: User {user} exceeded quota. Usage: {usage_bytes}, Quota: {quota}"

        # Check if log contains this user
        user_in_log = any(f"User {user} " in line for line in log_content)

        if usage_bytes > quota:
            assert expected_log_line in log_content, f"Expected alert for {user} not found or incorrect. Expected: '{expected_log_line}'"
        else:
            assert not user_in_log, f"Found unexpected alert for {user} who did not exceed quota."


def test_monitor_script_executes_du_and_drives_legacy_alerter():
    users_path = "/home/user/users_list.txt"
    quotas_path = "/home/user/quotas.json"
    alerter_path = "/home/user/bin/legacy_alerter"
    alert_path = "/home/user/alert.log"
    data_root = "/home/user/data/users"
    users = ["verifier_over_a", "verifier_under", "verifier_over_b"]
    test_dirs = [os.path.join(data_root, u) for u in users]
    call_log = tempfile.mktemp(prefix="legacy-calls-")
    du_log = tempfile.mktemp(prefix="du-calls-")

    def snapshot(path):
        if not os.path.exists(path):
            return None
        st = os.stat(path)
        with open(path, 'rb') as f:
            return (f.read(), stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)

    def restore(path, saved):
        if saved is None:
            if os.path.exists(path):
                os.unlink(path)
            return
        data, mode, uid, gid = saved
        with open(path, 'wb') as f:
            f.write(data)
        os.chmod(path, mode)
        os.chown(path, uid, gid)

    saved = {p: snapshot(p) for p in (users_path, quotas_path, alerter_path, alert_path)}
    du_target = os.path.realpath(shutil.which('du'))
    du_real = du_target + '.verifier-real'
    du_replaced = False

    try:
        for path in test_dirs:
            if os.path.exists(path):
                shutil.rmtree(path)
            os.makedirs(path, mode=0o777)
        with open(os.path.join(test_dirs[0], 'payload'), 'wb') as f:
            f.write(b'A' * 3179)
        with open(os.path.join(test_dirs[1], 'payload'), 'wb') as f:
            f.write(b'B' * 811)
        with open(os.path.join(test_dirs[2], 'payload'), 'wb') as f:
            f.write(b'C' * 5237)
        for path in test_dirs:
            os.chmod(path, 0o777)
            os.chmod(os.path.join(path, 'payload'), 0o666)

        usages = {}
        for user in users:
            out = subprocess.check_output(['du', '-sb', os.path.join(data_root, user)], text=True)
            usages[user] = int(out.split()[0])
        quotas = {
            users[0]: usages[users[0]] - 1,
            users[1]: usages[users[1]] + 1000,
            users[2]: usages[users[2]] - 7,
        }

        with open(users_path, 'w') as f:
            f.write('\n'.join(users) + '\n')
        with open(quotas_path, 'w') as f:
            json.dump(quotas, f)
        os.chmod(users_path, 0o644)
        os.chmod(quotas_path, 0o644)

        open(call_log, 'w').close()
        os.chmod(call_log, 0o666)
        mock = f'''#!/bin/bash
printf 'Enter username: '
IFS= read -r uname || exit 20
printf 'Enter current usage (bytes): '
IFS= read -r usage || exit 21
printf 'Enter quota (bytes): '
IFS= read -r quota || exit 22
printf 'Confirm alert (y/n)? '
IFS= read -r confirm || exit 23
printf '%s\\t%s\\t%s\\t%s\\n' "$uname" "$usage" "$quota" "$confirm" >> {call_log!r}
'''
        with open(alerter_path, 'w') as f:
            f.write(mock)
        os.chmod(alerter_path, 0o755)

        with open(alert_path, 'w') as f:
            f.write('')
        os.chmod(alert_path, 0o666)

        # Interpose the system du binary so execution, not source text, proves
        # that each monitored directory is queried with exactly du -sb.
        assert not os.path.exists(du_real), f"Temporary verifier path already exists: {du_real}"
        os.rename(du_target, du_real)
        du_replaced = True
        open(du_log, 'w').close()
        os.chmod(du_log, 0o666)
        wrapper = f'''#!/bin/sh
if [ "$#" -eq 2 ] && [ "$1" = "-sb" ]; then
    printf '%s\\n' "$2" >> {du_log!r}
fi
exec {du_real!r} "$@"
'''
        with open(du_target, 'w') as f:
            f.write(wrapper)
        os.chmod(du_target, 0o755)

        result = subprocess.run(
            ['runuser', '-u', 'user', '--', SCRIPT_PATH],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert result.returncode == 0, (
            f"monitor_script failed with exit code {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        with open(du_log) as f:
            du_calls = [line.rstrip('\n') for line in f]
        for user in users:
            required_path = os.path.join(data_root, user)
            assert required_path in du_calls, f"monitor_script did not execute du -sb {required_path}"

        with open(call_log) as f:
            calls = [line.rstrip('\n').split('\t') for line in f if line.strip()]
        expected = [
            [users[0], str(usages[users[0]]), str(quotas[users[0]]), 'y'],
            [users[2], str(usages[users[2]]), str(quotas[users[2]]), 'y'],
        ]
        assert calls == expected, (
            "legacy_alerter was not invoked with the exact interactive responses "
            f"for only the over-quota users. Expected {expected!r}, got {calls!r}"
        )
    finally:
        if du_replaced:
            try:
                if os.path.exists(du_target):
                    os.unlink(du_target)
            finally:
                if os.path.exists(du_real):
                    os.rename(du_real, du_target)
        for path, content in saved.items():
            restore(path, content)
        for path in test_dirs:
            if os.path.exists(path):
                shutil.rmtree(path)
        for path in (call_log, du_log):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
