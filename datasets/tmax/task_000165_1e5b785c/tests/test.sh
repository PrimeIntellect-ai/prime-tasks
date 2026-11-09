#!/bin/bash
set -e
mkdir -p /logs/verifier

if (
    set -e

    PROJECT=/home/user/audio_pr
    CGI="$PROJECT/api/cgi-bin/process.sh"
    REAL_CGI="$PROJECT/api/cgi-bin/process.sh.verifier-real"
    TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
    MARKER="/tmp/api-hit-$TOKEN"
    CAPTURE="/tmp/api-response-$TOKEN"
    API_PID=""

    cleanup() {
        if [ -n "$API_PID" ]; then
            kill -- -"$API_PID" 2>/dev/null || true
            wait "$API_PID" 2>/dev/null || true
        fi
        if [ -f "$REAL_CGI" ]; then
            mv -f "$REAL_CGI" "$CGI"
        fi
        rm -f "$MARKER" "$CAPTURE" /tmp/verifier_probe_*.wav /tmp/verifier_probe_*.json
    }
    trap cleanup EXIT

    # Build from a clean build directory using the requested standard CMake flow.
    rm -rf "$PROJECT/build"
    cmake -S "$PROJECT" -B "$PROJECT/build"
    cmake --build "$PROJECT/build"

    test -f "$PROJECT/build/libenvelope.so"
    test -x "$PROJECT/build/envelope_cli"

    # The ABI symbol must really be exported, and the CLI must dynamically need
    # the submitted shared library rather than merely existing beside it.
    nm -D --defined-only "$PROJECT/build/libenvelope.so" | awk '$NF == "compute_envelope" { found=1 } END { exit !found }'
    readelf -d "$PROJECT/build/envelope_cli" | grep -E 'NEEDED.*libenvelope\.so' >/dev/null

    test -f /home/user/run_test.sh

    # Nothing may already be listening on the API port before the integration
    # test starts its own server.
    python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.25)
try:
    listening = s.connect_ex(("127.0.0.1", 8080)) == 0
finally:
    s.close()
raise SystemExit(1 if listening else 0)
PY

    # Temporarily wrap the submitted CGI. This proves run_test.sh reached that
    # endpoint and records the exact CGI response body for provenance checking.
    mv "$CGI" "$REAL_CGI"
    chmod +x "$REAL_CGI"
    cat > "$CGI" <<WRAP
#!/bin/bash
printf '%s' '$TOKEN' > '$MARKER'
set -o pipefail
'$REAL_CGI' | tee '$CAPTURE'
WRAP
    chmod +x "$CGI"

    rm -f /home/user/output.json
    timeout 45s bash /home/user/run_test.sh

    test -f "$MARKER"
    test "$(cat "$MARKER")" = "$TOKEN"
    test -s "$CAPTURE"
    test -f /home/user/output.json

    # output.json must be the body returned by the invoked CGI, not a separately
    # calculated replacement.
    python3 - "$CAPTURE" /home/user/output.json <<'PY'
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
if b"\r\n\r\n" in raw:
    body = raw.split(b"\r\n\r\n", 1)[1]
elif b"\n\n" in raw:
    body = raw.split(b"\n\n", 1)[1]
else:
    raise SystemExit("captured CGI output has no header terminator")
out = pathlib.Path(sys.argv[2]).read_bytes()
if body != out:
    raise SystemExit("output.json is not the exact CGI response body")
PY

    # The integration script must have stopped the server it started.
    stopped=0
    for _ in $(seq 1 30); do
        if python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.1)
try:
    active = s.connect_ex(("127.0.0.1", 8080)) == 0
finally:
    s.close()
raise SystemExit(1 if active else 0)
PY
        then
            stopped=1
            break
        fi
        sleep 0.1
    done
    test "$stopped" -eq 1

    mv -f "$REAL_CGI" "$CGI"

    # Generate unpredictable WAV probes and derive their expected RMS values.
    python3 - <<'PY'
import json, secrets
import numpy as np
from scipy.io import wavfile

rng = np.random.default_rng(secrets.randbits(128))
for index, (rate, windows) in enumerate(((8000, 4), (11025, 3))):
    size = int(rate * 0.1)
    samples = rng.uniform(-0.8, 0.8, size * windows).astype(np.float32)
    wavfile.write(f"/tmp/verifier_probe_{index}.wav", rate, samples)
    expected = [float(np.sqrt(np.mean(samples[i*size:(i+1)*size] ** 2)))
                for i in range(windows)]
    with open(f"/tmp/verifier_probe_{index}.json", "w") as f:
        json.dump(expected, f)
PY

    # Start the submitted server and exercise the real CGI on both fresh inputs.
    cd "$PROJECT/api"
    setsid ./server.sh >/tmp/verifier-api.log 2>&1 &
    API_PID=$!
    ready=0
    for _ in $(seq 1 50); do
        if curl -fsS --max-time 1 http://127.0.0.1:8080/ >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.1
    done
    test "$ready" -eq 1

    for index in 0 1; do
        curl -fsS --max-time 10 \
            -H 'Content-Type: audio/wav' \
            --data-binary "@/tmp/verifier_probe_${index}.wav" \
            http://127.0.0.1:8080/cgi-bin/process.sh \
            -o "/tmp/verifier_probe_${index}.actual.json"
    done

    kill -- -"$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
    API_PID=""

    cat > /tmp/test_final_state.py <<'PYTEST'
import os
import json
import math
import numpy as np
import pytest


def calculate_mse(reference_json_path, predicted_json_path):
    with open(reference_json_path, 'r') as f:
        y_true = np.array(json.load(f))
    try:
        with open(predicted_json_path, 'r') as f:
            y_pred = np.array(json.load(f))
    except Exception:
        return 9999.0

    if len(y_true) != len(y_pred):
        min_len = min(len(y_true), len(y_pred))
        mse = np.mean((y_true[:min_len] - y_pred[:min_len])**2)
        mse += abs(len(y_true) - len(y_pred)) * 1.0
        return float(mse)

    return float(np.mean((y_true - y_pred)**2))


def test_run_test_sh_exists():
    path = "/home/user/run_test.sh"
    assert os.path.isfile(path), f"Integration test script {path} does not exist."


def test_output_json_exists():
    path = "/home/user/output.json"
    assert os.path.isfile(path), f"Output file {path} does not exist."


def test_envelope_mse_metric():
    ref_path = "/root/reference_envelope.json"
    pred_path = "/home/user/output.json"

    assert os.path.isfile(ref_path), f"Reference file {ref_path} missing. Environment setup issue."
    assert os.path.isfile(pred_path), f"Predicted file {pred_path} missing."

    mse = calculate_mse(ref_path, pred_path)
    threshold = 0.001
    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}. Output array does not match the reference envelope."


def test_output_is_strict_flat_finite_numeric_array():
    with open('/home/user/output.json') as f:
        value = json.load(f)
    assert isinstance(value, list)
    assert value
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in value)
    assert all(math.isfinite(float(x)) for x in value)


@pytest.mark.parametrize('index', [0, 1])
def test_fresh_audio_through_cgi(index):
    expected_path = f'/tmp/verifier_probe_{index}.json'
    actual_path = f'/tmp/verifier_probe_{index}.actual.json'
    with open(expected_path) as f:
        expected = json.load(f)
    with open(actual_path) as f:
        actual = json.load(f)
    assert isinstance(actual, list)
    assert len(actual) == len(expected)
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in actual)
    assert all(math.isfinite(float(x)) for x in actual)
    mse = float(np.mean((np.asarray(expected, dtype=float) - np.asarray(actual, dtype=float)) ** 2))
    assert mse <= 1e-8, f'fresh CGI probe {index} has MSE {mse}'
PYTEST

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
