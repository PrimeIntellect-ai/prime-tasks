#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests

INTEGRATOR_DIR = Path('/home/user/app/integrator')
SERVER_BINARY = '/tmp/integrator-verifier-build'
AUTH = {'Authorization': 'Bearer ds-model-fit-token'}


def _kill_port_8080():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == '1F90':
                inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            pass

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.5)


def _wait_for_integrator(proc):
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f'Compiled Go integrator exited early with status {proc.returncode}.')
        try:
            requests.post('http://localhost:8080/solve', timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.2)
    pytest.fail('Compiled Go integrator did not start on port 8080.')


@pytest.fixture(scope='session', autouse=True)
def run_submitted_integrator():
    assert INTEGRATOR_DIR.is_dir(), 'Integrator source directory is missing.'
    env = os.environ.copy()
    env['GO111MODULE'] = 'off'
    build = subprocess.run(
        ['go', 'build', '-o', SERVER_BINARY, '.'],
        cwd=INTEGRATOR_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert build.returncode == 0, f'Go integrator does not compile:\n{build.stdout}'

    _kill_port_8080()
    proc = subprocess.Popen(
        [SERVER_BINARY],
        cwd=INTEGRATOR_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _wait_for_integrator(proc)
    yield
    # Leave the submitted service running, as required by the task.


def test_services_running():
    try:
        res = requests.get('http://localhost:5000/results', timeout=2)
        assert res.status_code in [200, 404, 405], 'Aggregator service did not respond properly.'
    except requests.exceptions.RequestException:
        pytest.fail('Aggregator service is not running on port 5000.')

    try:
        res = requests.post('http://localhost:8080/solve', timeout=2)
        assert res.status_code == 401, f'Expected 401 Unauthorized without header, got {res.status_code}'
    except requests.exceptions.RequestException:
        pytest.fail('Go Integrator service is not running on port 8080.')


def test_go_integrator_auth():
    for value in ('Bearer wrong-token', 'ds-model-fit-token', '', 'Basic Zm9vOmJhcg=='):
        res = requests.post(
            'http://localhost:8080/solve',
            headers={'Authorization': value},
            timeout=5,
        )
        assert res.status_code == 401, f'Invalid authorization {value!r} returned {res.status_code}'

    try:
        res = requests.post('http://localhost:8080/solve', headers=AUTH, timeout=10)
        assert res.status_code in [200, 202], f'Expected success with auth header, got {res.status_code}'
    except requests.exceptions.RequestException:
        pytest.fail('Failed to connect to Go Integrator service with auth header.')


def test_results_log_exists_and_matches_aggregator():
    results_path = '/home/user/results.log'
    assert os.path.exists(results_path), f'{results_path} does not exist.'
    assert os.path.getsize(results_path) > 0, f'{results_path} is empty.'

    res = requests.get('http://localhost:5000/results', timeout=3)
    assert res.status_code == 200, f'Aggregator /results returned {res.status_code}'
    expected = res.json()
    with open(results_path, 'r') as f:
        logged = json.load(f)
    assert logged == expected, 'results.log is not the output currently returned by the aggregator.'


def test_solver_fixed_source_assertions():
    solver_path = INTEGRATOR_DIR / 'solver.go'
    assert solver_path.is_file(), f'{solver_path} is missing.'
    content = solver_path.read_text()
    assert '1e-6' in content, 'The minimum step size 1e-6 is not enforced in solver.go.'
    assert 'math.Pow' in content or 'Pow(' in content or '1e-6' in content, 'Step size adaptation logic does not seem to be fixed.'


def test_adapt_step_behavior():
    with tempfile.TemporaryDirectory() as td:
        work = Path(td) / 'integrator'
        shutil.copytree(INTEGRATOR_DIR, work)
        test_file = work / 'solver_behavior_test.go'
        test_file.write_text(r'''package main

import (
    "math"
    "testing"
)

func TestAdaptStepFormulaAndClamp(t *testing.T) {
    cases := []struct{ dt, err, tol float64 }{
        {0.01, 0.0001, 0.000001},
        {0.0257, 0.0000031, 0.000091},
        {0.0000023, 900000000.0, 0.0000017},
        {0.31, 0.0082, 0.0082},
        {0.0041, 0.0000000027, 0.00000083},
    }
    for _, c := range cases {
        want := c.dt * math.Pow(c.tol/c.err, 0.2)
        if want < 1e-6 {
            want = 1e-6
        }
        got := adaptStep(c.dt, c.err, c.tol)
        if math.IsNaN(got) || math.IsInf(got, 0) {
            t.Fatalf("adaptStep(%g,%g,%g) returned non-finite %g", c.dt, c.err, c.tol, got)
        }
        if got < 1e-6 {
            t.Fatalf("adaptStep returned %g, below minimum 1e-6", got)
        }
        scale := math.Max(1, math.Abs(want))
        if math.Abs(got-want) > 1e-12*scale {
            t.Fatalf("adaptStep(%g,%g,%g)=%g; want %g", c.dt, c.err, c.tol, got, want)
        }
    }
}
''')
        env = os.environ.copy()
        env['GO111MODULE'] = 'off'
        result = subprocess.run(
            ['go', 'test', '.'], cwd=work, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
        )
        assert result.returncode == 0, f'adaptStep failed behavioral tests:\n{result.stdout}'


def test_main_parallel():
    main_path = INTEGRATOR_DIR / 'main.go'
    assert main_path.is_file(), f'{main_path} is missing.'
    content = main_path.read_text()
    assert 'sync.WaitGroup' in content or 'WaitGroup' in content, 'WaitGroup is missing in main.go.'
    assert 'go ' in content, 'Goroutines are not used in main.go.'

    checker = Path('/tmp/check_parallel.go')
    checker.write_text(r'''package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { panic(err) }
    found, hasGo, hasWG, hasAdd, hasWait := false, false, false, false, false
    ast.Inspect(f, func(n ast.Node) bool {
        fn, ok := n.(*ast.FuncDecl)
        if !ok || fn.Name.Name != "ProcessNetworks" { return true }
        found = true
        ast.Inspect(fn.Body, func(x ast.Node) bool {
            switch v := x.(type) {
            case *ast.GoStmt:
                hasGo = true
            case *ast.Ident:
                if v.Name == "WaitGroup" { hasWG = true }
            case *ast.SelectorExpr:
                if v.Sel.Name == "WaitGroup" { hasWG = true }
                if v.Sel.Name == "Add" { hasAdd = true }
                if v.Sel.Name == "Wait" { hasWait = true }
            }
            return true
        })
        return false
    })
    if !(found && hasGo && hasWG && hasAdd && hasWait) {
        fmt.Fprintf(os.Stderr, "ProcessNetworks must create a WaitGroup, Add work, launch a goroutine, and Wait (found=%v go=%v wg=%v add=%v wait=%v)\n", found, hasGo, hasWG, hasAdd, hasWait)
        os.Exit(1)
    }
}
''')
    result = subprocess.run(
        ['go', 'run', str(checker), str(main_path)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
    )
    assert result.returncode == 0, result.stdout
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
