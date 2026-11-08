#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pathlib
import secrets
import shutil
import struct
import subprocess

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

APP = pathlib.Path('/app/telemparser')
TOOL = pathlib.Path('/home/user/workspace/statstool')
KEY = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'


def run(cmd, cwd, timeout=120):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def test_statstool_exists():
    assert (TOOL / 'main.go').is_file(), 'statstool main.go is missing'
    assert (TOOL / 'go.mod').is_file(), 'statstool go.mod is missing'


def test_telemparser_tests_pass():
    assert (APP / 'parser_test.go').is_file(), 'parser_test.go is missing in /app/telemparser'
    result = run(['go', 'test', '-count=1', './...'], APP)
    assert result.returncode == 0, f'go test failed in /app/telemparser:\n{result.stdout}\n{result.stderr}'


def make_encrypted(path, key, values):
    plaintext = b''.join(struct.pack('>i', value) for value in values)
    nonce = secrets.token_bytes(12)
    path.write_bytes(nonce + AESGCM(key).encrypt(nonce, plaintext, None))


def parse_mean(result, expected, label):
    assert result.returncode == 0, f'{label} failed:\n{result.stdout}\n{result.stderr}'
    output = result.stdout.strip()
    assert len(output.split()) == 1, f'{label} must print only one floating-point value, got: {result.stdout!r}'
    try:
        actual = float(output)
    except ValueError:
        raise AssertionError(f'{label} output is not a valid float: {output!r}')
    assert math.isfinite(actual), f'{label} returned a non-finite value: {actual}'
    tolerance = max(1e-7, abs(expected) * 1e-12)
    assert abs(actual - expected) <= tolerance, f'{label}: got {actual}, expected {expected}'


def test_statstool_and_package_on_derived_cases(tmp_path):
    compiled = tmp_path / 'statstool'
    result = run(['go', 'build', '-o', str(compiled)], TOOL)
    assert result.returncode == 0, f'Failed to compile statstool:\n{result.stderr}\n{result.stdout}'

    # Retain the original held-out assertion.
    original = run([str(compiled), '/testdata/eval.bin.enc', KEY], TOOL)
    parse_mean(original, 14502394.25, 'statstool on original evaluation data')

    # The executable must really depend on the requested package.
    deps = run(['go', 'list', '-deps', '.'], TOOL)
    assert deps.returncode == 0, f'go list failed:\n{deps.stdout}\n{deps.stderr}'
    assert 'telemparser' in deps.stdout.splitlines(), 'statstool does not import the telemparser module'

    random_values = [struct.unpack('>i', secrets.token_bytes(4))[0] for _ in range(1003)]
    cases = [
        [2_000_000_000] * 137 + [1_700_000_000] * 89 + [-31337] * 11,
        [-2_000_000_000] * 103 + [1_900_000_000] * 307 + [17] * 29,
        random_values,
    ]

    probe_dir = tmp_path / 'parserprobe'
    probe_dir.mkdir()
    (probe_dir / 'go.mod').write_text('module verifierprobe\n\ngo 1.20\n\nrequire telemparser v0.0.0\nreplace telemparser => /app/telemparser\n')
    (probe_dir / 'main.go').write_text('''package main
import (
  "fmt"
  "os"
  "telemparser"
)
func main() {
  if len(os.Args) != 3 { os.Exit(2) }
  mean, err := telemparser.CalculateMean(os.Args[1], os.Args[2])
  if err != nil { panic(err) }
  fmt.Printf("%.17g\\n", mean)
}
''')
    probe = probe_dir / 'probe'
    result = run(['go', 'build', '-o', str(probe)], probe_dir)
    assert result.returncode == 0, f'Could not build direct telemparser probe:\n{result.stdout}\n{result.stderr}'

    for index, values in enumerate(cases):
        key = secrets.token_bytes(32)
        encrypted = tmp_path / f'case-{index}.enc'
        make_encrypted(encrypted, key, values)
        expected = sum(values) / len(values)
        hex_key = key.hex()
        parse_mean(run([str(compiled), str(encrypted), hex_key], TOOL), expected, f'statstool case {index}')
        parse_mean(run([str(probe), str(encrypted), hex_key], probe_dir), expected, f'telemparser case {index}')

    for args in ([], ['/testdata/eval.bin.enc'], ['/testdata/eval.bin.enc', KEY, 'extra']):
        bad = run([str(compiled), *args], TOOL)
        assert bad.returncode != 0, f'statstool must reject {len(args)} arguments'


def test_regression_test_detects_int32_aggregation_bug(tmp_path):
    fixed_source = r'''package telemparser

import (
    "crypto/aes"
    "crypto/cipher"
    "encoding/binary"
    "encoding/hex"
    "errors"
    "io/ioutil"
)

func CalculateMean(filename, hexKey string) (float64, error) {
    key, err := hex.DecodeString(hexKey)
    if err != nil { return 0, err }
    data, err := ioutil.ReadFile(filename)
    if err != nil { return 0, err }
    block, err := aes.NewCipher(key)
    if err != nil { return 0, err }
    aesgcm, err := cipher.NewGCM(block)
    if err != nil { return 0, err }
    nonceSize := aesgcm.NonceSize()
    if len(data) < nonceSize { return 0, errors.New("ciphertext too short") }
    plaintext, err := aesgcm.Open(nil, data[:nonceSize], data[nonceSize:], nil)
    if err != nil { return 0, err }
    if len(plaintext)%4 != 0 { return 0, errors.New("invalid data length") }
    var sum int64 = 0
    count := len(plaintext) / 4
    for i := 0; i < len(plaintext); i += 4 {
        val := int32(binary.BigEndian.Uint32(plaintext[i:i+4]))
        sum += int64(val)
    }
    if count == 0 { return 0, nil }
    return float64(sum) / float64(count), nil
}
'''
    buggy_source = fixed_source.replace('var sum int64 = 0', 'var sum int32 = 0').replace('sum += int64(val)', 'sum += val')

    def fixture(name, source):
        directory = tmp_path / name
        directory.mkdir()
        (directory / 'go.mod').write_text('module telemparser\n\ngo 1.20\n')
        (directory / 'parser.go').write_text(source)
        for test_file in APP.glob('*_test.go'):
            shutil.copy2(test_file, directory / test_file.name)
        if (APP / 'testdata').is_dir():
            shutil.copytree(APP / 'testdata', directory / 'testdata')
        return directory

    fixed = fixture('fixed', fixed_source)
    fixed_result = run(['go', 'test', '-count=1', './...'], fixed)
    assert fixed_result.returncode == 0, ('parser_test.go does not pass with a correct overflow-safe parser:\n'
                                          + fixed_result.stdout + '\n' + fixed_result.stderr)

    buggy = fixture('buggy', buggy_source)
    buggy_result = run(['go', 'test', '-count=1', './...'], buggy)
    assert buggy_result.returncode != 0, 'parser_test.go does not detect the original int32 aggregation overflow bug'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
