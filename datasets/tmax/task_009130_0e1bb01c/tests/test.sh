#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
from pathlib import Path

ORIGINAL_SENSOR = '''package sensor

import (
\t"encoding/base64"
\t"encoding/json"
)

type Payload struct {
\tSignature string    `json:"signature"`
\tReadings  []float32 `json:"readings"`
}

func ProcessPayload(data []byte) (float64, []byte, error) {
\tvar p Payload
\tif err := json.Unmarshal(data, &p); err != nil {
\t\treturn 0, nil, err
\t}

\tsig, err := base64.StdEncoding.DecodeString(p.Signature)
\tif err != nil {
\t\treturn 0, nil, err
\t}

\tvar sum float64
\tfor _, r := range p.Readings {
\t\tsum += float64(r)
\t}

\treturn sum, sig, nil
}
'''

ORIGINAL_TEST = '''package sensor

import (
\t"crypto/rand"
\t"encoding/base64"
\t"encoding/json"
\t"math"
\tmrand "math/rand"
\t"testing"
\t"time"
)

func TestProcessPayload(t *testing.T) {
\tmrand.Seed(time.Now().UnixNano())

\tfor i := 0; i < 100; i++ {
\t\tsig := make([]byte, 16)
\t\trand.Read(sig)
\t\tsigStr := base64.URLEncoding.EncodeToString(sig)

\t\tvar readings []float64
\t\tvar expectedSum float64
\t\tfor j := 0; j < 50; j++ {
\t\t\tval := mrand.Float64() * 50
\t\t\treadings = append(readings, val)
\t\t\texpectedSum += val
\t\t}

\t\ttype testPayload struct {
\t\t\tSignature string    `json:"signature"`
\t\t\tReadings  []float64 `json:"readings"`
\t\t}

\t\ttp := testPayload{
\t\t\tSignature: sigStr,
\t\t\tReadings:  readings,
\t\t}

\t\tdata, _ := json.Marshal(tp)

\t\tactualSum, decodedSig, err := ProcessPayload(data)
\t\tif err != nil {
\t\t\tt.Fatalf("Failed to process payload: %v", err)
\t\t}

\t\tif string(decodedSig) != string(sig) {
\t\t\tt.Fatalf("Signature mismatch")
\t\t}

\t\tif math.Abs(expectedSum-actualSum) > 1e-4 {
\t\t\tt.Fatalf("Sum mismatch: expected %f, got %f", expectedSum, actualSum)
\t\t}
\t}
}
'''


def test_sensor_test_was_not_modified():
    path = Path('/home/user/sensor/sensor_test.go')
    assert path.is_file(), f'File {path} does not exist'
    assert path.read_text() == ORIGINAL_TEST, 'sensor_test.go was modified'


def test_reproduce_sh_exists_and_executable():
    path = '/home/user/reproduce.sh'
    assert os.path.isfile(path), f'File {path} does not exist'

    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f'File {path} is not executable'

    with open(path, 'r') as f:
        content = f.read()
        assert 'go test' in content, f"File {path} does not appear to run 'go test'"

    # Simulate two successful test runs followed by a failure. A valid reproducer
    # must keep running through the successes and stop immediately at the failure.
    with tempfile.TemporaryDirectory() as td:
        fake_go = Path(td) / 'go'
        count_file = Path(td) / 'count'
        fake_go.write_text(f'''#!/bin/sh
count=0
[ ! -f "{count_file}" ] || count=$(cat "{count_file}")
count=$((count + 1))
echo "$count" > "{count_file}"
[ "$PWD" = "/home/user/sensor" ] || exit 91
[ "$1" = "test" ] || exit 92
[ "$count" -lt 3 ] || exit 42
exit 0
''')
        fake_go.chmod(0o755)
        env = os.environ.copy()
        env['PATH'] = td + os.pathsep + env.get('PATH', '')
        try:
            subprocess.run([path], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=5)
        except subprocess.TimeoutExpired:
            assert False, 'reproduce.sh did not exit after go test failed'
        count = int(count_file.read_text()) if count_file.exists() else 0
        assert count == 3, f'reproduce.sh should stop on the first failure; go was called {count} times'


def test_fix_patch_exists_and_valid():
    path = '/home/user/fix.patch'
    assert os.path.isfile(path), f'File {path} does not exist'

    with open(path, 'r') as f:
        content = f.read()
        assert '---' in content and '+++' in content, f'File {path} does not look like a valid unified diff/patch file'

    # Require one unified-diff file section and apply its hunks to the pristine
    # sensor.go. Header paths are normalized so both git and ordinary diff output
    # are accepted while the actual hunks still must apply with zero fuzz.
    lines = content.splitlines(keepends=True)
    old_headers = [i for i, line in enumerate(lines) if line.startswith('--- ')]
    new_headers = [i for i, line in enumerate(lines) if line.startswith('+++ ')]
    assert len(old_headers) == 1 and len(new_headers) == 1, 'fix.patch must patch only sensor.go'
    assert new_headers[0] == old_headers[0] + 1, 'fix.patch has malformed unified-diff headers'
    assert 'sensor_test.go' not in content, 'fix.patch must not modify sensor_test.go'

    normalized = list(lines)
    normalized[old_headers[0]] = '--- sensor.go\n'
    normalized[new_headers[0]] = '+++ sensor.go\n'

    with tempfile.TemporaryDirectory() as td:
        target = Path(td) / 'sensor.go'
        target.write_text(ORIGINAL_SENSOR)
        patch_file = Path(td) / 'fix.patch'
        patch_file.write_text(''.join(normalized))
        result = subprocess.run(
            ['patch', '--batch', '--forward', '--fuzz=0', '-p0', '-i', str(patch_file)],
            cwd=td, capture_output=True, text=True
        )
        assert result.returncode == 0, f'fix.patch does not cleanly apply to original sensor.go:\n{result.stdout}\n{result.stderr}'
        assert target.read_text() == Path('/home/user/sensor/sensor.go').read_text(), \
            'Applying fix.patch does not reproduce the submitted sensor.go'


def test_sensor_go_fixed():
    path = '/home/user/sensor/sensor.go'
    assert os.path.isfile(path), f'File {path} does not exist'

    with open(path, 'r') as f:
        content = f.read()
        assert '[]float64' in content, 'Payload Readings should be changed to float64 to fix precision issues'
        assert 'base64.URLEncoding' in content, 'Should use base64.URLEncoding to fix the parsing issue'


def test_process_payload_behavior():
    hidden_test = Path('/home/user/sensor/verifier_behavior_test.go')
    assert not hidden_test.exists(), 'Unexpected verifier_behavior_test.go already exists'
    hidden_test.write_text(r'''package sensor

import (
    "bytes"
    "encoding/base64"
    "encoding/json"
    "math"
    "testing"
)

func TestVerifierProcessPayloadBehavior(t *testing.T) {
    signature := []byte{251, 255, 239, 250, 0, 127}
    readings := []float64{16777217, 0.125, 3.141592653589793, 0.000000000123}
    payload := struct {
        Signature string `json:"signature"`
        Readings []float64 `json:"readings"`
    }{base64.URLEncoding.EncodeToString(signature), readings}
    data, err := json.Marshal(payload)
    if err != nil { t.Fatal(err) }
    gotSum, gotSignature, err := ProcessPayload(data)
    if err != nil { t.Fatalf("ProcessPayload rejected URL-safe payload: %v", err) }
    if !bytes.Equal(gotSignature, signature) { t.Fatalf("decoded signature mismatch") }
    wantSum := 0.0
    for _, value := range readings { wantSum += value }
    if math.Abs(gotSum-wantSum) > 1e-10 {
        t.Fatalf("precision mismatch: want %.15g, got %.15g", wantSum, gotSum)
    }
}
''')
    try:
        result = subprocess.run(['go', 'test', '-count=1'], cwd='/home/user/sensor',
                                capture_output=True, text=True)
        assert result.returncode == 0, f'behavioral test failed:\n{result.stdout}\n{result.stderr}'
    finally:
        hidden_test.unlink(missing_ok=True)


def test_go_test_passes_consistently():
    # Run go test multiple times to ensure the intermittent failures are fixed
    for i in range(10):
        result = subprocess.run(
            ['go', 'test'],
            cwd='/home/user/sensor',
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f'go test failed on run {i+1}. Output:\n{result.stdout}\n{result.stderr}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
