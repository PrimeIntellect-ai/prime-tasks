#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pwd
import signal
import subprocess
import time
import urllib.request

import pytest
import semver

PROJECT = '/home/user/project'


def expected_version():
    versions = []
    with open(os.path.join(PROJECT, 'versions.txt'), 'r', encoding='utf-8') as f:
        for raw_line in f:
            line = raw_line.strip()
            if line.startswith('libA-'):
                versions.append(semver.Version.parse(line[len('libA-'):]))
    lower = semver.Version.parse('1.1.0')
    upper = semver.Version.parse('2.0.0')
    eligible = [v for v in versions if v >= lower and v < upper]
    assert eligible, 'versions.txt contains no eligible libA version'
    selected = str(max(eligible))
    assert selected == '1.3.0-alpha', 'The supplied versions.txt was modified or resolved incorrectly'
    return selected


def expected_config():
    with open(os.path.join(PROJECT, 'legacy_config.b64'), 'rb') as f:
        decoded = base64.b64decode(f.read(), validate=True).decode('utf-8')
    result = {}
    for line in decoded.splitlines():
        if line:
            key, value = line.split('=', 1)
            result[key] = value
    expected = {'PORT': '9090', 'MODE': 'production', 'DB': 'sqlite'}
    assert result == expected, 'The supplied legacy_config.b64 was modified'
    return result


def test_config_json():
    """Verify config.json is generated correctly from legacy_config.b64."""
    config_path = os.path.join(PROJECT, 'config.json')
    assert os.path.isfile(config_path), f'{config_path} is missing. Did build.py run successfully?'

    with open(config_path, 'r', encoding='utf-8') as f:
        try:
            config_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{config_path} does not contain valid JSON.')

    expected = expected_config()
    assert config_data == expected, f'config.json contents {config_data} do not match expected {expected}.'


def test_nginx_conf():
    """Verify nginx.conf exists and contains the correct configuration."""
    nginx_conf_path = os.path.join(PROJECT, 'nginx.conf')
    assert os.path.isfile(nginx_conf_path), f'{nginx_conf_path} is missing.'

    with open(nginx_conf_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'proxy_pass' in content and '127.0.0.1:9090' in content, \
        'nginx.conf does not contain proxy_pass to http://127.0.0.1:9090'

    version = expected_version()
    assert 'add_header' in content and 'X-Library-Version' in content and version in content, \
        f'nginx.conf does not contain the correct add_header directive for X-Library-Version {version}'


def test_test_report_log():
    """Verify test_report.log contains the correct status, header, and body."""
    report_path = os.path.join(PROJECT, 'test_report.log')
    assert os.path.isfile(report_path), f'{report_path} is missing. Did test_suite.py run successfully?'

    with open(report_path, 'r', encoding='utf-8') as f:
        lines = f.read().strip().splitlines()

    status_line = next((line for line in lines if line.startswith('STATUS:')), None)
    header_line = next((line for line in lines if line.startswith('HEADER:')), None)
    body_line = next((line for line in lines if line.startswith('BODY:')), None)

    assert status_line is not None, 'test_report.log is missing the STATUS: line'
    assert header_line is not None, 'test_report.log is missing the HEADER: line'
    assert body_line is not None, 'test_report.log is missing the BODY: line'

    assert '200' in status_line, f'Expected STATUS to contain 200, got: {status_line}'
    version = expected_version()
    assert version in header_line, f'Expected HEADER to contain {version}, got: {header_line}'

    body_str = body_line.replace('BODY:', '', 1).strip()
    try:
        body_json = json.loads(body_str)
    except json.JSONDecodeError:
        pytest.fail(f'BODY line does not contain valid JSON. Got: {body_str}')

    expected_body = expected_config()
    assert body_json == expected_body, f'Parsed BODY {body_json} does not match expected {expected_body}'


def test_live_reverse_proxy():
    """Actually launch the generated system and exercise the proxy."""
    user = pwd.getpwnam('user')

    def demote():
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    backend = None
    nginx = None
    nginx_cmd = ['/usr/sbin/nginx', '-p', PROJECT + '/', '-c', os.path.join(PROJECT, 'nginx.conf')]
    try:
        backend = subprocess.Popen(
            ['python3', os.path.join(PROJECT, 'backend.py')],
            cwd=PROJECT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=demote,
            start_new_session=True,
        )
        time.sleep(0.4)
        assert backend.poll() is None, 'backend.py failed to start on 127.0.0.1:9090'

        nginx = subprocess.Popen(
            nginx_cmd,
            cwd=PROJECT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=demote,
            start_new_session=True,
        )
        time.sleep(0.4)
        if nginx.poll() is not None:
            assert nginx.returncode == 0, 'nginx failed to start with the generated nginx.conf'

        last_error = None
        response = None
        for _ in range(30):
            try:
                response = urllib.request.urlopen('http://127.0.0.1:8080/', timeout=1)
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.1)
        assert response is not None, f'Could not reach the generated reverse proxy: {last_error}'

        with response:
            status = response.status
            header = response.headers.get('X-Library-Version')
            raw_body = response.read().decode('utf-8')

        assert status == 200, f'Expected live proxy status 200, got {status}'
        assert header == expected_version(), f'Expected live X-Library-Version {expected_version()}, got {header}'
        assert json.loads(raw_body) == expected_config(), f'Unexpected live response body: {raw_body}'
    finally:
        if nginx is not None and nginx.poll() is None:
            try:
                os.killpg(nginx.pid, signal.SIGTERM)
                nginx.wait(timeout=5)
            except Exception:
                try:
                    os.killpg(nginx.pid, signal.SIGKILL)
                except Exception:
                    pass
        elif nginx is not None:
            subprocess.run(
                nginx_cmd + ['-s', 'stop'],
                cwd=PROJECT,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=demote,
                timeout=5,
                check=False,
            )
        if backend is not None and backend.poll() is None:
            try:
                os.killpg(backend.pid, signal.SIGTERM)
                backend.wait(timeout=5)
            except Exception:
                try:
                    os.killpg(backend.pid, signal.SIGKILL)
                except Exception:
                    pass
TEST_EOF

cat << 'RUN_EOF' > /tmp/run_verification.sh
#!/bin/bash
set -e
PROJECT=/home/user/project

test -f "$PROJECT/build.py"
test -f "$PROJECT/test_suite.py"

# Remove stale services and generated artifacts so pre-fabricated files cannot pass.
pkill -u user -f '/home/user/project/backend.py' 2>/dev/null || true
pkill -u user -f 'nginx' 2>/dev/null || true
rm -f "$PROJECT/config.json" "$PROJECT/nginx.conf" "$PROJECT/test_report.log"

timeout 30s runuser -u user -- bash -c 'cd /home/user/project && python3 build.py'
test -f "$PROJECT/config.json"
test -f "$PROJECT/nginx.conf"
timeout 45s runuser -u user -- bash -c 'cd /home/user/project && python3 test_suite.py'
test -f "$PROJECT/test_report.log"

python3 -m pytest /tmp/test_final_state.py -x --tb=short
RUN_EOF
chmod +x /tmp/run_verification.sh

if timeout 90s /tmp/run_verification.sh 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
