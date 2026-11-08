#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

SCRIPT=/home/user/bin/deploy_pipeline.py

# Stop any server recorded by the agent's initial deployment before exercising
# the deployment runner on a fresh, verifier-generated artifact.
python3 - <<'PY'
import os
import shutil
import signal
import time

pid_file = '/home/user/app_root/server.pid'
if os.path.isfile(pid_file):
    try:
        pid = int(open(pid_file).read().strip())
        cmdline_path = f'/proc/{pid}/cmdline'
        if os.path.exists(cmdline_path):
            with open(cmdline_path, 'rb') as f:
                cmdline = f.read()
            if b'server.py' in cmdline:
                os.kill(pid, signal.SIGTERM)
                time.sleep(0.2)
    except (ValueError, OSError):
        pass
shutil.rmtree('/home/user/app_root', ignore_errors=True)
PY

# Generate a fresh artifact whose contents cannot be satisfied by copying the
# files from the image's original app.zip. Keep the documented target paths so
# the required exact cron entry remains applicable.
python3 - <<'PY'
import json
import os
import uuid
import zipfile

marker = uuid.uuid4().hex
artifact = f'/home/user/build/verifier-{marker}.zip'
server_source = (
    'import time\n'
    f"with open('/home/user/app_root/.verifier_started', 'w') as f:\n"
    f"    f.write({marker!r})\n"
    'time.sleep(10000)\n'
)
health_source = f'print("health-{marker}")\n'

with zipfile.ZipFile(artifact, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('server.py', server_source)
    zf.writestr('healthcheck.py', health_source)

payload = {
    'artifact': artifact,
    'target_dir': '/home/user/app_root',
    'disk_image': '/home/user/storage.img',
    'mount_point': '/home/user/app_root/storage',
}
with open('/home/user/ci_webhook.json', 'w') as f:
    json.dump(payload, f)
with open('/tmp/deploy_verifier_case.json', 'w') as f:
    json.dump({'marker': marker, 'artifact': artifact}, f)
os.chmod('/home/user/ci_webhook.json', 0o666)
PY

# Reset simulated system state and include a pre-existing cron job to ensure
# the runner preserves it.
printf 'preexisting fstab entry\n' > /home/user/mock_fstab
printf '17 3 * * * /bin/true\n' | crontab -

# The requested artifact must exist and must itself perform the deployment.
test -f "$SCRIPT"
timeout 20s python3 "$SCRIPT" </dev/null >/tmp/deploy_pipeline.out 2>/tmp/deploy_pipeline.err

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import time
import zipfile


def load_case():
    with open('/tmp/deploy_verifier_case.json') as f:
        return json.load(f)


def test_deployment_script_exists():
    script = '/home/user/bin/deploy_pipeline.py'
    assert os.path.isfile(script), f"Deployment script {script} does not exist"


def test_mock_fstab_updated():
    fstab_path = '/home/user/mock_fstab'
    assert os.path.exists(fstab_path), f"{fstab_path} does not exist"
    with open(fstab_path, 'r') as f:
        content = f.read()
    expected_line = '/home/user/storage.img /home/user/app_root/storage ext4 defaults 0 2'
    assert expected_line in content, f"Expected line '{expected_line}' not found in {fstab_path}"
    assert 'preexisting fstab entry' in content, 'Existing fstab content was overwritten'


def test_crontab_updated():
    try:
        cron_output = subprocess.check_output(['crontab', '-l'], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        cron_output = e.output

    expected_cron = '*/5 * * * * /usr/bin/python3 /home/user/app_root/healthcheck.py >> /home/user/health.log 2>&1'
    assert expected_cron in cron_output, 'Expected crontab entry not found in crontab -l'
    assert '17 3 * * * /bin/true' in cron_output, 'Existing cron job was overwritten'


def test_files_extracted():
    server_py = '/home/user/app_root/server.py'
    healthcheck_py = '/home/user/app_root/healthcheck.py'
    assert os.path.isfile(server_py), f"Extracted file {server_py} does not exist"
    assert os.path.isfile(healthcheck_py), f"Extracted file {healthcheck_py} does not exist"


def test_extracted_files_match_payload_artifact():
    case = load_case()
    with zipfile.ZipFile(case['artifact']) as zf:
        expected_server = zf.read('server.py')
        expected_health = zf.read('healthcheck.py')
    with open('/home/user/app_root/server.py', 'rb') as f:
        actual_server = f.read()
    with open('/home/user/app_root/healthcheck.py', 'rb') as f:
        actual_health = f.read()
    assert actual_server == expected_server, 'server.py does not match the artifact from the JSON payload'
    assert actual_health == expected_health, 'healthcheck.py does not match the artifact from the JSON payload'


def test_server_running_and_pid_file():
    pid_file = '/home/user/app_root/server.pid'
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist"

    with open(pid_file, 'r') as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID"
    pid = int(pid_str)

    cmdline_file = f'/proc/{pid}/cmdline'
    assert os.path.exists(cmdline_file), f"Process with PID {pid} is not running (no {cmdline_file})"

    with open(cmdline_file, 'r') as f:
        cmdline = f.read()

    assert 'server.py' in cmdline, f"Process {pid} is running but its cmdline does not contain 'server.py'"
    assert '/home/user/app_root/server.py' in cmdline, f"Process {pid} is not running the extracted server.py"


def test_extracted_server_was_started():
    case = load_case()
    marker_path = '/home/user/app_root/.verifier_started'
    deadline = time.time() + 5
    while time.time() < deadline and not os.path.isfile(marker_path):
        time.sleep(0.05)
    assert os.path.isfile(marker_path), 'The extracted server.py did not start'
    with open(marker_path) as f:
        assert f.read() == case['marker'], 'Start marker was not produced by the verifier artifact'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
