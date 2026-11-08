#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
import time
import uuid

import numpy as np
import pytest
import scipy.io.wavfile as wavfile


def proc_entries():
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode('utf-8', 'replace')
            yield name, cmd
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue


def test_nginx_config_updated_and_effective():
    path = '/home/user/nginx.conf'
    assert os.path.isfile(path), f'Nginx config file is missing at {path}.'
    with open(path, 'r') as f:
        content = f.read()
    expected = 'proxy_pass http://unix:/home/user/api.sock;'
    assert expected in content, f"Nginx config does not contain the correct upstream socket path. Expected to find '{expected}'."

    result = subprocess.run(
        ['nginx', '-T', '-c', path], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f'Nginx configuration is not valid:\n{result.stderr}'
    effective = result.stdout + result.stderr
    assert expected in effective, 'The effective Nginx configuration does not use /home/user/api.sock.'
    assert '/home/user/tmp/wrong.sock' not in effective, 'The effective Nginx configuration still references the incorrect socket.'
    assert any('nginx' in cmd for _, cmd in proc_entries()), 'Nginx is not running.'


def test_backend_script_updated_and_effective():
    path = '/home/user/start_backend.sh'
    assert os.path.isfile(path), f'Backend startup script is missing at {path}.'
    with open(path, 'r') as f:
        content = f.read()
    assert 'TZ=Europe/Paris' in content, 'The environment variable TZ=Europe/Paris is not set in the backend startup script.'
    assert 'LC_ALL=fr_FR.UTF-8' in content, 'The environment variable LC_ALL=fr_FR.UTF-8 is not set in the backend startup script.'

    capture = tempfile.mktemp(prefix='backend_env_', dir='/tmp')
    probe = r'''
python3() {
    printf '%s\n%s\n' "$TZ" "$LC_ALL" > "$CAPTURE"
    printf '%s\n' "$@" >> "$CAPTURE"
}
source /home/user/start_backend.sh
wait
'''
    env = os.environ.copy()
    env['CAPTURE'] = capture
    try:
        result = subprocess.run(
            ['bash', '-c', probe], cwd='/home/user', env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, f'Backend startup script could not be executed: {result.stderr}'
        assert os.path.isfile(capture), 'The backend startup script did not invoke Python.'
        with open(capture) as f:
            values = f.read().splitlines()
        assert len(values) >= 2
        assert values[0] == 'Europe/Paris', 'TZ is not effective when the backend is launched.'
        assert values[1] == 'fr_FR.UTF-8', 'LC_ALL is not effective when the backend is launched.'
        args = ' '.join(values[2:])
        assert 'uvicorn' in args and 'backend:app' in args and '/home/user/api.sock' in args, 'The startup script does not launch the expected backend on /home/user/api.sock.'
    finally:
        if os.path.exists(capture):
            os.unlink(capture)

    assert os.path.exists('/home/user/api.sock'), 'The backend Unix socket does not exist.'
    assert stat.S_ISSOCK(os.stat('/home/user/api.sock').st_mode), '/home/user/api.sock is not a Unix socket.'

    backend_pids = []
    for pid, cmd in proc_entries():
        if 'uvicorn' in cmd and 'backend:app' in cmd and '/home/user/api.sock' in cmd:
            backend_pids.append(pid)
    assert backend_pids, 'The backend Uvicorn process is not running on /home/user/api.sock.'

    effective_env = False
    for pid in backend_pids:
        try:
            with open(f'/proc/{pid}/environ', 'rb') as f:
                entries = set(f.read().split(b'\0'))
            if b'TZ=Europe/Paris' in entries and b'LC_ALL=fr_FR.UTF-8' in entries:
                effective_env = True
                break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert effective_env, 'The running backend does not have the required TZ and LC_ALL environment.'


def test_crontab_configured():
    try:
        output = subprocess.check_output(['crontab', '-l']).decode('utf-8')
    except subprocess.CalledProcessError:
        pytest.fail('Failed to list crontab. Is it configured?')

    expected_cron = '0 * * * * /home/user/cleanup.sh'
    assert expected_cron in output, f"Crontab does not contain the expected scheduled task. Expected to find '{expected_cron}'."
    active_lines = [line.strip() for line in output.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    assert expected_cron in active_lines, 'The cleanup command is not configured as an exact active hourly cron entry.'


def test_cleanup_script_exists_and_deletes_only_old_tmp_files():
    path = '/home/user/cleanup.sh'
    assert os.path.isfile(path), f'Cleanup script is missing at {path}.'
    assert os.access(path, os.X_OK), 'cleanup.sh is not executable by cron.'

    token = uuid.uuid4().hex
    old_tmp = f'/home/user/verify_{token}_old.tmp'
    fresh_tmp = f'/home/user/verify_{token}_fresh.tmp'
    old_other = f'/home/user/verify_{token}_old.txt'
    paths = [old_tmp, fresh_tmp, old_other]
    try:
        for item in paths:
            with open(item, 'w') as f:
                f.write(token)
            os.chown(item, 1000, 1000)
        old = time.time() - 3 * 24 * 60 * 60
        os.utime(old_tmp, (old, old))
        os.utime(old_other, (old, old))

        result = subprocess.run(
            ['runuser', '-u', 'user', '--', path],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, f'cleanup.sh failed when run as the user: {result.stderr}'
        assert not os.path.exists(old_tmp), 'cleanup.sh did not delete a .tmp file older than 2 days.'
        assert os.path.exists(fresh_tmp), 'cleanup.sh incorrectly deleted a recent .tmp file.'
        assert os.path.exists(old_other), 'cleanup.sh incorrectly deleted an old non-.tmp file.'
    finally:
        for item in paths:
            if os.path.exists(item):
                os.unlink(item)


def test_audio_processing_metric():
    processed_file = '/home/user/processed_audio.wav'
    original_file = '/app/voicemail.wav'
    golden_file = '/tmp/golden_reference.wav'

    assert os.path.isfile(processed_file), f'Processed audio file is missing at {processed_file}.'
    assert os.path.isfile(original_file), f'Original audio file is missing at {original_file}.'

    cmd = [
        'ffmpeg', '-y', '-i', original_file,
        '-ar', '8000', '-ac', '1', '-af', 'lowpass=f=3000',
        golden_file
    ]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Failed to generate golden reference audio: {e.stderr.decode()}')

    try:
        rate1, data1 = wavfile.read(processed_file)
    except Exception as e:
        pytest.fail(f'Failed to read processed audio file: {e}')
    try:
        rate2, data2 = wavfile.read(golden_file)
    except Exception as e:
        pytest.fail(f'Failed to read golden reference audio file: {e}')

    assert rate1 == rate2, f'Sample rate mismatch: processed file is {rate1}Hz, expected {rate2}Hz.'
    assert rate1 == 8000, f'Processed audio sample rate is {rate1}Hz, expected 8000Hz.'
    assert data1.ndim == 1, 'Processed audio is not mono.'
    assert data2.ndim == 1
    assert len(data1) == len(data2), f'Processed audio length is {len(data1)} samples, expected {len(data2)}.'
    assert len(data1) > 0, 'Processed audio is empty.'

    d1 = data1.astype(np.float32)
    d2 = data2.astype(np.float32)
    mse = np.mean((d1 - d2) ** 2)
    threshold = 10.0
    assert np.isfinite(mse), 'Audio processing metric is not finite.'
    assert mse <= threshold, f'Audio processing failed metric check: MSE is {mse:.4f}, which is > threshold {threshold}.'


def test_saved_api_response_is_real_and_complete():
    path = '/home/user/api_response.txt'
    assert os.path.isfile(path), f'API response file is missing at {path}. The pipeline test was likely not completed.'
    assert os.path.getsize(path) > 0, 'The saved API response is empty.'
    try:
        with open(path) as f:
            response = json.load(f)
    except Exception as e:
        pytest.fail(f'The saved API response is not valid JSON: {e}')
    assert response.get('filename') == 'processed_audio.wav', 'The saved response is not for processed_audio.wav.'
    assert response.get('tz') == 'Europe/Paris', 'The saved response does not show the required backend timezone.'
    assert response.get('lc') == 'fr_FR.UTF-8', 'The saved response does not show the required backend locale.'

    access_log = '/home/user/access.log'
    assert os.path.isfile(access_log), 'Nginx access log is missing; no proxied upload was recorded.'
    with open(access_log, errors='replace') as f:
        log = f.read()
    assert re.search(r'"POST /upload(?:\?[^ ]*)? HTTP/[^\"]+" 2\d\d ', log), 'Nginx did not record a successful POST to /upload.'


def test_live_proxy_and_backend_upload():
    token = uuid.uuid4().hex
    upload_name = f'verifier_{token}.bin'
    upload_path = f'/tmp/{upload_name}'
    response_path = f'/tmp/response_{token}.json'
    headers_path = f'/tmp/headers_{token}.txt'
    try:
        with open(upload_path, 'wb') as f:
            f.write(os.urandom(257))
        result = subprocess.run([
            'curl', '--silent', '--show-error', '--max-time', '8',
            '--dump-header', headers_path,
            '--output', response_path, '--write-out', '%{http_code}',
            '-F', f'file=@{upload_path};filename={upload_name}',
            'http://127.0.0.1:8080/upload'
        ], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, f'Live upload through Nginx failed: {result.stderr}'
        assert result.stdout == '200', f'Live upload returned HTTP {result.stdout}, expected 200.'
        with open(headers_path, errors='replace') as f:
            headers = f.read()
        assert re.search(r'(?im)^server:\s*nginx(?:/|\s|$)', headers), 'Port 8080 response was not served through Nginx.'
        with open(response_path) as f:
            response = json.load(f)
        assert response.get('filename') == upload_name, 'The backend did not process the verifier upload.'
        assert response.get('tz') == 'Europe/Paris', 'The live backend has the wrong TZ environment.'
        assert response.get('lc') == 'fr_FR.UTF-8', 'The live backend has the wrong LC_ALL environment.'
    finally:
        for item in (upload_path, response_path, headers_path):
            if os.path.exists(item):
                os.unlink(item)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
