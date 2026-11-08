#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

import pytest

ROOT = Path('/home/user/manager')
BINARY = ROOT / 'artifact-server'
FINAL_MANIFEST = Path('/home/user/final_manifest.json')


def calc_signature(data: bytes) -> int:
    sig = sum(b * (i + 1) for i, b in enumerate(data))
    return sig % 1000003


def copy_project(destination: Path):
    shutil.copytree(
        ROOT,
        destination,
        ignore=shutil.ignore_patterns('artifact-server', '*.test'),
    )


def run_checked(command, cwd, timeout=120):
    result = subprocess.run(
        command,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, result.stdout
    return result


def stop_existing_artifact_servers():
    target = os.path.realpath(BINARY)
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes().split(b'\0')
            first_arg = os.path.realpath(os.fsdecode(cmdline[0])) if cmdline and cmdline[0] else ''
            exe = os.path.realpath(entry / 'exe')
            if first_arg == target or exe == target:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            pass
    time.sleep(0.3)


def start_server(cwd: Path):
    stop_existing_artifact_servers()
    proc = subprocess.Popen(
        [str(BINARY)],
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    last_error = None
    for _ in range(60):
        if proc.poll() is not None:
            output = proc.stdout.read().decode(errors='replace') if proc.stdout else ''
            pytest.fail(f'artifact-server exited before serving requests:\n{output}')
        try:
            response = urllib.request.urlopen('http://127.0.0.1:8080/manifest', timeout=1)
            return proc, response
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    proc.terminate()
    proc.wait(timeout=5)
    pytest.fail(f'artifact-server did not listen on port 8080: {last_error}')


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def test_build_script_effects():
    go_mod_path = ROOT / 'go.mod'
    assert go_mod_path.exists(), f'Go module file {go_mod_path} does not exist. build.sh may not have run correctly.'

    go_mod_content = go_mod_path.read_text()
    assert 'module manager' in go_mod_content, "go.mod does not contain 'module manager'."
    module_lines = [line.strip() for line in go_mod_content.splitlines() if line.strip().startswith('module ')]
    assert module_lines and module_lines[0] == 'module manager', 'The Go module name must be exactly manager.'

    assert BINARY.exists(), f'Executable {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'File {BINARY} is not executable.'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'artifact-server is not a compiled Linux executable.'

    with tempfile.TemporaryDirectory() as td:
        project = Path(td) / 'manager'
        copy_project(project)
        for name in ('go.mod', 'go.sum', 'artifact-server'):
            path = project / name
            if path.exists():
                path.unlink()

        # This valid but deliberately unformatted source proves that build.sh runs formatting.
        (project / 'format_probe.go').write_text('package main\nimport "fmt"\nvar _=fmt.Sprintf\n')
        result = run_checked(['bash', './build.sh'], project)

        rebuilt_mod = project / 'go.mod'
        rebuilt_binary = project / 'artifact-server'
        assert rebuilt_mod.exists(), f'build.sh did not initialize go.mod:\n{result.stdout}'
        rebuilt_module_lines = [line.strip() for line in rebuilt_mod.read_text().splitlines() if line.strip().startswith('module ')]
        assert rebuilt_module_lines and rebuilt_module_lines[0] == 'module manager', 'build.sh did not initialize module manager.'
        assert rebuilt_binary.exists() and os.access(rebuilt_binary, os.X_OK), 'build.sh did not build artifact-server.'
        assert rebuilt_binary.read_bytes()[:4] == b'\x7fELF', 'build.sh did not produce a compiled executable.'
        formatting = run_checked(['gofmt', '-l', '.'], project)
        assert formatting.stdout.strip() == '', f'build.sh did not format all Go source files:\n{formatting.stdout}'


def test_calculate_signature_directly():
    rng = random.Random(917263)
    cases = [b'', b'HELLO', bytes(range(256)), bytes(rng.randrange(256) for _ in range(4096))]
    cases.extend(bytes(rng.randrange(256) for _ in range(rng.randrange(1, 700))) for _ in range(8))

    with tempfile.TemporaryDirectory() as td:
        project = Path(td) / 'manager'
        copy_project(project)
        entries = []
        for data in cases:
            byte_values = ','.join(str(value) for value in data)
            entries.append(f'{{[]byte{{{byte_values}}}, uint32({calc_signature(data)})}}')
        test_source = '''package algo
import "testing"
func TestVerifierCalculateSignature(t *testing.T) {
 cases := []struct { data []byte; want uint32 }{%s}
 for i, tc := range cases {
  if got := CalculateSignature(tc.data); got != tc.want {
   t.Fatalf("case %%d: got %%d, want %%d", i, got, tc.want)
  }
 }
}
''' % ','.join(entries)
        (project / 'algo' / 'algo_verifier_test.go').write_text(test_source)
        run_checked(['go', 'test', './algo'], project)


def test_manifest_handler_directly():
    rng = random.Random(662901)
    manifest = {f'dynamic-{i}-{rng.randrange(100000)}.bin': rng.randrange(0, 1000003) for i in range(7)}
    go_entries = ','.join(json.dumps(k) + f': uint32({v})' for k, v in manifest.items())

    with tempfile.TemporaryDirectory() as td:
        project = Path(td) / 'manager'
        copy_project(project)
        test_source = '''package api
import (
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "reflect"
 "strings"
 "testing"
)
func TestVerifierManifestHandler(t *testing.T) {
 want := map[string]uint32{%s}
 server := &Server{Manifest: want}
 req := httptest.NewRequest(http.MethodGet, "/manifest", nil)
 rec := httptest.NewRecorder()
 server.ManifestHandler(rec, req)
 if rec.Code != http.StatusOK { t.Fatalf("status: got %%d, want 200", rec.Code) }
 if ct := rec.Header().Get("Content-Type"); strings.Split(ct, ";")[0] != "application/json" {
  t.Fatalf("Content-Type: got %%q", ct)
 }
 var got map[string]uint32
 if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil { t.Fatalf("invalid JSON: %%v", err) }
 if !reflect.DeepEqual(got, want) { t.Fatalf("manifest: got %%v, want %%v", got, want) }
}
''' % go_entries
        (project / 'api' / 'api_verifier_test.go').write_text(test_source)
        run_checked(['go', 'test', './api'], project)


def test_final_manifest_content():
    assert FINAL_MANIFEST.exists(), f'Final manifest file {FINAL_MANIFEST} does not exist.'
    try:
        manifest_data = json.loads(FINAL_MANIFEST.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'File {FINAL_MANIFEST} does not contain valid JSON.')

    artifacts_dir = ROOT / 'artifacts'
    assert artifacts_dir.exists(), f'Artifacts directory {artifacts_dir} does not exist.'

    expected_manifest = {}
    for filename in os.listdir(artifacts_dir):
        if filename.endswith('.bin'):
            expected_manifest[filename] = calc_signature((artifacts_dir / filename).read_bytes())

    assert isinstance(manifest_data, dict), 'Manifest JSON should be an object (dictionary).'
    for filename, expected_sig in expected_manifest.items():
        assert filename in manifest_data, f'Artifact {filename} is missing from the final manifest.'
        assert manifest_data[filename] == expected_sig, f'Incorrect signature for {filename}. Expected {expected_sig}, got {manifest_data[filename]}.'
    for key in manifest_data.keys():
        assert key in expected_manifest, f'Unexpected artifact {key} found in the final manifest.'

    proc = None
    try:
        proc, response = start_server(ROOT)
        body = response.read()
        assert response.status == 200, f'/manifest returned HTTP {response.status}.'
        assert response.headers.get_content_type() == 'application/json', 'Live server Content-Type is not application/json.'
        assert body == FINAL_MANIFEST.read_bytes(), 'final_manifest.json is not the exact response produced by artifact-server.'
    finally:
        if proc is not None:
            stop_server(proc)


def test_running_server_with_derived_artifacts():
    rng = random.Random(380144)
    generated = {
        'probe-a.bin': bytes(rng.randrange(256) for _ in range(37)),
        'probe-b.bin': bytes(rng.randrange(256) for _ in range(1025)),
        'probe-c.bin': bytes(rng.randrange(256) for _ in range(4096)),
    }
    expected = {name: calc_signature(data) for name, data in generated.items()}

    with tempfile.TemporaryDirectory() as td:
        workdir = Path(td)
        artifacts = workdir / 'artifacts'
        artifacts.mkdir()
        for name, data in generated.items():
            (artifacts / name).write_bytes(data)
        (artifacts / 'ignored.txt').write_bytes(b'not an artifact')

        proc = None
        try:
            proc, response = start_server(workdir)
            body = response.read()
            assert response.status == 200, f'/manifest returned HTTP {response.status}.'
            assert response.headers.get_content_type() == 'application/json', 'Content-Type must be application/json.'
            got = json.loads(body)
            assert got == expected, f'Running artifact-server returned {got}, expected {expected}.'
        finally:
            if proc is not None:
                stop_server(proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
