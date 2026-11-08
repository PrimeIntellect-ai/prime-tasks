#!/bin/bash
set +e
mkdir -p /logs/verifier
RESULT=0

cleanup() {
    nginx -s quit -c /home/user/project/nginx.conf >/dev/null 2>&1 || true
    [ -n "${NGINX_PID:-}" ] && kill "$NGINX_PID" >/dev/null 2>&1 || true
    [ -n "${API_PID:-}" ] && kill "$API_PID" >/dev/null 2>&1 || true
    pkill -x nginx >/dev/null 2>&1 || true
    pkill -f '^python3 .*\/home/user/project/api.py' >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The requested environment must really be installable.
python3 -m pip install -r /home/user/project/requirements.txt >/tmp/verifier_pip.log 2>&1 || RESULT=1

# Restore the supplied fixture deterministically before exercising the agent's test.
python3 - <<'PY' || RESULT=1
import numpy as np
from scipy.io import wavfile
sample_rate = 44100
t = np.linspace(0, 1, sample_rate, False)
audio = (np.sin(440 * t * 2 * np.pi) * 10000).astype(np.int16)
wavfile.write('/app/audio/sample.wav', sample_rate, audio)
PY

# Do not allow an already-running service to satisfy the checks.
pkill -x nginx >/dev/null 2>&1 || true
pkill -f '^python3 .*\/home/user/project/api.py' >/dev/null 2>&1 || true
sleep 1

if [ -f /home/user/project/api.py ]; then
    (cd /home/user/project && exec python3 api.py) >/tmp/verifier_api.log 2>&1 &
    API_PID=$!
else
    RESULT=1
fi

wait_for_port() {
    python3 - "$1" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
for _ in range(100):
    s = socket.socket()
    s.settimeout(0.1)
    try:
        s.connect(('127.0.0.1', port))
        s.close()
        raise SystemExit(0)
    except OSError:
        s.close()
        time.sleep(0.1)
raise SystemExit(1)
PY
}

wait_for_port 5000 || RESULT=1

# The API itself must not be masquerading as the proxy on port 8000.
python3 - <<'PY' || RESULT=1
import socket
s = socket.socket()
s.settimeout(0.3)
try:
    s.connect(('127.0.0.1', 8000))
except OSError:
    raise SystemExit(0)
finally:
    s.close()
raise SystemExit(1)
PY

nginx -t -c /home/user/project/nginx.conf >/tmp/verifier_nginx_test.log 2>&1 || RESULT=1
nginx -c /home/user/project/nginx.conf >/tmp/verifier_nginx.log 2>&1 &
NGINX_PID=$!
wait_for_port 8000 || RESULT=1

cat <<'PYTEST' > /tmp/test_live_service.py
import io
import re
import subprocess
import numpy as np
import requests
from scipy.io import wavfile


def test_nginx_effective_configuration():
    p = subprocess.run(
        ['nginx', '-T', '-c', '/home/user/project/nginx.conf'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert p.returncode == 0, p.stdout
    conf = p.stdout
    assert re.search(r'\blisten\s+[^;]*\b8000\b[^;]*;', conf), conf
    assert re.search(r'\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;', conf), conf


def test_live_random_audio_through_proxy():
    rng = np.random.default_rng(847291)
    source = rng.integers(-9000, 9001, size=6137, dtype=np.int16)
    source[0] = 12000
    source[1] = -11000
    buf = io.BytesIO()
    wavfile.write(buf, 32017, source)

    response = requests.post(
        'http://127.0.0.1:8000/process',
        files={'audio': ('challenge.wav', buf.getvalue(), 'audio/wav')},
        timeout=15,
    )
    assert response.status_code == 200, response.text[:500]

    rate, output = wavfile.read(io.BytesIO(response.content))
    assert rate == 32017
    assert output.dtype == np.int16
    assert output.shape == source.shape

    out_float = output.astype(np.float64)
    peak = np.max(np.abs(out_float))
    dbfs = 20 * np.log10(peak / 32768.0) if peak else -100.0
    assert abs(dbfs - (-3.0)) <= 0.1, dbfs

    # A fixed or fabricated WAV cannot pass: every challenge sample must be
    # the corresponding peak-scaled source sample (allowing integer rounding).
    expected = source.astype(np.float64) * (peak / 12000.0)
    assert np.max(np.abs(out_float - expected)) <= 2.0
PYTEST

python3 -m pytest /tmp/test_live_service.py -x --tb=short || RESULT=1

# The submitted pytest suite must itself create the required output through the
# running integration stack. Removing the old file prevents stale output passing.
rm -f /home/user/project/processed_audio.wav
(cd /home/user/project && python3 -m pytest test_api.py -x --tb=short) || RESULT=1

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import numpy as np
from scipy.io import wavfile


def test_nginx_conf_exists():
    path = "/home/user/project/nginx.conf"
    assert os.path.isfile(path), f"Nginx config {path} is missing."


def test_api_script_exists():
    path = "/home/user/project/api.py"
    assert os.path.isfile(path), f"API script {path} is missing."


def test_test_script_exists():
    path = "/home/user/project/test_api.py"
    assert os.path.isfile(path), f"Test script {path} is missing."


def test_required_dependencies_are_declared():
    path = '/home/user/project/requirements.txt'
    assert os.path.isfile(path)
    declared = set()
    for line in open(path, encoding='utf-8'):
        line = line.split('#', 1)[0].strip()
        match = re.match(r'([A-Za-z0-9_.-]+)', line)
        if match:
            declared.add(match.group(1).lower().replace('_', '-'))
    required = {'flask', 'pytest', 'requests', 'numpy', 'scipy'}
    assert required <= declared, f'Missing requirements: {sorted(required - declared)}'


def test_submitted_test_has_required_fixture_and_targets():
    path = '/home/user/project/test_api.py'
    source = open(path, encoding='utf-8').read()
    tree = ast.parse(source, filename=path)
    has_fixture = any(
        isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and
        any((isinstance(d, ast.Name) and d.id == 'fixture') or
            (isinstance(d, ast.Attribute) and d.attr == 'fixture') or
            (isinstance(d, ast.Call) and isinstance(d.func, ast.Attribute) and d.func.attr == 'fixture')
            for d in node.decorator_list)
        for node in ast.walk(tree)
    )
    assert has_fixture, 'test_api.py must contain a pytest fixture'
    for required_text in ('requests', '/app/audio/sample.wav', 'localhost:8000/process',
                          'audio', '/home/user/project/processed_audio.wav'):
        assert required_text in source, f'test_api.py is missing {required_text!r}'


def test_processed_audio_metric():
    target_file = "/home/user/project/processed_audio.wav"
    assert os.path.isfile(target_file), f"Processed audio file {target_file} is missing. The test script may not have run successfully or saved the output."

    try:
        sample_rate, data = wavfile.read(target_file)
    except Exception as e:
        assert False, f"Failed to read {target_file} as a WAV file: {e}"

    if len(data.shape) > 1:
        data = data[:, 0]

    peak_amplitude = np.max(np.abs(data.astype(np.float64)))
    if peak_amplitude == 0:
        dbfs = -100.0
    else:
        dbfs = 20 * np.log10(peak_amplitude / 32768.0)

    metric = abs(dbfs - (-3.0))
    threshold = 0.1
    assert metric <= threshold, f"Peak volume normalization failed. Expected -3.0 dBFS, got {dbfs:.2f} dBFS (Difference: {metric:.4f} > {threshold})."


def test_processed_audio_is_normalized_supplied_sample():
    in_rate, source = wavfile.read('/app/audio/sample.wav')
    out_rate, output = wavfile.read('/home/user/project/processed_audio.wav')
    assert out_rate == in_rate
    assert output.dtype == np.int16
    assert output.shape == source.shape
    source_f = source.astype(np.float64)
    output_f = output.astype(np.float64)
    source_peak = np.max(np.abs(source_f))
    output_peak = np.max(np.abs(output_f))
    assert source_peak > 0 and output_peak > 0
    expected = source_f * (output_peak / source_peak)
    assert np.max(np.abs(output_f - expected)) <= 2.0
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short || RESULT=1

if [ "$RESULT" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
