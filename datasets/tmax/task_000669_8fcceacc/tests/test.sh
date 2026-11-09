#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import shutil
import stat
import subprocess
import textwrap
from pathlib import Path

import pytest

PIPELINE = Path('/home/user/pipeline')
SCRIPT = PIPELINE / 'regression_test.sh'

EXPECTED_FETCHER_TEST = '''package pipeline

import (
\t"context"
\t"runtime"
\t"testing"
\t"time"
)

func TestFetchDataLeak(t *testing.T) {
\tinitialGoroutines := runtime.NumGoroutine()

\tctx, cancel := context.WithTimeout(context.Background(), 2*time.Millisecond)
\tdefer cancel()

\turls := []string{"url1", "url2", "url3", "url4", "url5"}
\tFetchData(ctx, urls)

\t// Wait a bit to let any blocked goroutines settle
\ttime.Sleep(50 * time.Millisecond)

\tfinalGoroutines := runtime.NumGoroutine()
\tif finalGoroutines > initialGoroutines+1 { // Allowing 1 for the test runner overhead
\t\tt.Fatalf("Goroutine leak detected! Initial: %d, Final: %d", initialGoroutines, finalGoroutines)
\t}
}
'''

EXPECTED_AGGREGATOR_TEST = '''import unittest
import ast
from aggregator import aggregate_prices

class TestAggregator(unittest.TestCase):
    def test_uses_decimal(self):
        with open('aggregator.py', 'r') as f:
            source = f.read()

        self.assertIn('Decimal', source, "Must use the Decimal module for precision")

    def test_sum(self):
        self.assertEqual(aggregate_prices([0.1, 0.1, 0.1]), "0.30")
        self.assertEqual(aggregate_prices([1.01, 2.02]), "3.03")

if __name__ == '__main__':
    unittest.main()
'''


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def assert_ok(result, description):
    assert result.returncode == 0, (
        f'{description} failed with exit code {result.returncode}. '
        f'STDOUT: {result.stdout} STDERR: {result.stderr}'
    )


def test_provided_tests_were_not_modified():
    assert (PIPELINE / 'fetcher_test.go').read_text() == EXPECTED_FETCHER_TEST
    assert (PIPELINE / 'test_aggregator.py').read_text() == EXPECTED_AGGREGATOR_TEST


def test_regression_script_exists_and_executable():
    script_path = "/home/user/pipeline/regression_test.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_regression_script_execution():
    result = run([str(SCRIPT)], cwd=PIPELINE)
    assert_ok(result, 'regression_test.sh')


def _make_wrappers(tmp_path):
    real_go = shutil.which('go')
    real_python = shutil.which('python3')
    assert real_go and real_python

    bindir = tmp_path / 'bin'
    bindir.mkdir()
    wrappers = {
        'go': (real_go, 'go'),
        'python3': (real_python, 'python3'),
    }
    for name, (real_command, tool) in wrappers.items():
        wrapper = bindir / name
        wrapper.write_text(textwrap.dedent(f'''\
            #!/bin/bash
            printf '%s\\t%s\\t%s\\n' '{tool}' "$PWD" "$*" >> "$VERIFY_LOG"
            if [ "${{FAIL_TOOL:-}}" = '{tool}' ]; then
                exit 47
            fi
            exec {real_command!r} "$@"
        '''))
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return bindir


def test_regression_script_really_runs_and_propagates_both_commands(tmp_path):
    bindir = _make_wrappers(tmp_path)
    log = tmp_path / 'commands.log'
    env = os.environ.copy()
    env['PATH'] = str(bindir) + os.pathsep + env.get('PATH', '')
    env['VERIFY_LOG'] = str(log)

    result = run([str(SCRIPT)], cwd=PIPELINE, env=env)
    assert_ok(result, 'instrumented regression_test.sh')
    entries = [line.split('\t', 2) for line in log.read_text().splitlines()]
    assert any(tool == 'go' and cwd == str(PIPELINE) and args.split()[:1] == ['test']
               for tool, cwd, args in entries), 'regression_test.sh did not run go test in the pipeline directory'
    assert any(tool == 'python3' and cwd == str(PIPELINE) and args.split() == ['-m', 'unittest', 'test_aggregator.py']
               for tool, cwd, args in entries), 'regression_test.sh did not run the required Python unittest command'

    for failing_tool in ('go', 'python3'):
        failure_log = tmp_path / f'{failing_tool}.log'
        failing_env = env.copy()
        failing_env['VERIFY_LOG'] = str(failure_log)
        failing_env['FAIL_TOOL'] = failing_tool
        failed = run([str(SCRIPT)], cwd=PIPELINE, env=failing_env)
        assert failed.returncode != 0, f'regression_test.sh ignored failure of {failing_tool}'


def test_go_tests_pass():
    result = run(["go", "test", "./..."], cwd=PIPELINE)
    assert_ok(result, 'Go tests')


def test_fetch_data_functionality_and_cancellation_safety():
    hidden_test = PIPELINE / 'verifier_hidden_test.go'
    assert not hidden_test.exists(), f'unexpected pre-existing file: {hidden_test}'
    hidden_test.write_text(r'''package pipeline

import (
    "context"
    "fmt"
    "runtime"
    "sort"
    "testing"
    "time"
)

func verifierExpected(urls []string) []string {
    out := make([]string, len(urls))
    for i, u := range urls {
        out[i] = u + "_data"
    }
    sort.Strings(out)
    return out
}

func verifierSorted(values []string) []string {
    out := append([]string(nil), values...)
    sort.Strings(out)
    return out
}

func TestVerifierFetchDataReturnsEveryResult(t *testing.T) {
    cases := [][]string{
        nil,
        {"alpha"},
        {"x", "y", "x", "https://example.invalid/tick"},
    }
    many := make([]string, 128)
    for i := range many {
        many[i] = fmt.Sprintf("instrument-%03d", i)
    }
    cases = append(cases, many)

    for _, urls := range cases {
        got := verifierSorted(FetchData(context.Background(), urls))
        want := verifierExpected(urls)
        if len(got) != len(want) {
            t.Fatalf("FetchData(%d URLs) returned %d results; want %d", len(urls), len(got), len(want))
        }
        for i := range want {
            if got[i] != want[i] {
                t.Fatalf("FetchData result mismatch at %d: got %q, want %q", i, got[i], want[i])
            }
        }
    }
}

func TestVerifierRepeatedImmediateCancellationDoesNotLeak(t *testing.T) {
    runtime.GC()
    time.Sleep(30 * time.Millisecond)
    before := runtime.NumGoroutine()

    urls := make([]string, 100)
    for i := range urls {
        urls[i] = fmt.Sprintf("cancel-%d", i)
    }
    for round := 0; round < 20; round++ {
        ctx, cancel := context.WithCancel(context.Background())
        cancel()
        FetchData(ctx, urls)
    }

    time.Sleep(150 * time.Millisecond)
    runtime.GC()
    after := runtime.NumGoroutine()
    if after > before+8 {
        t.Fatalf("FetchData leaked goroutines over repeated cancellations: before=%d after=%d", before, after)
    }
}
''')
    try:
        result = run(['go', 'test', '-count=1', './...'], cwd=PIPELINE, timeout=30)
        assert_ok(result, 'hidden Go behavioral tests')
    finally:
        hidden_test.unlink(missing_ok=True)


def test_python_tests_pass():
    result = run(["python3", "-m", "unittest", "test_aggregator.py"], cwd=PIPELINE)
    assert_ok(result, 'Python tests')


def test_python_aggregator_uses_decimal():
    aggregator_path = "/home/user/pipeline/aggregator.py"
    with open(aggregator_path, "r") as f:
        content = f.read()
    assert "Decimal" in content, "The Python aggregator does not seem to use the Decimal module."


def test_python_aggregator_has_real_decimal_usage_and_exact_behavior(tmp_path):
    source = (PIPELINE / 'aggregator.py').read_text()
    tree = ast.parse(source)

    functions = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == 'aggregate_prices']
    assert len(functions) == 1, 'aggregate_prices must be defined exactly once'
    function = functions[0]
    assert not isinstance(function, ast.AsyncFunctionDef)
    assert len(function.args.args) == 1 and function.args.args[0].arg == 'prices'
    assert ast.unparse(function.args.args[0].annotation) == 'list[float]', 'prices annotation must remain list[float]'
    assert ast.unparse(function.returns) == 'str', 'return annotation must remain str'

    decimal_modules = set()
    decimal_constructors = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'decimal':
                    decimal_modules.add(alias.asname or 'decimal')
        elif isinstance(node, ast.ImportFrom) and node.module == 'decimal':
            for alias in node.names:
                if alias.name == 'Decimal':
                    decimal_constructors.add(alias.asname or 'Decimal')

    real_decimal_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in decimal_constructors:
            real_decimal_call = True
        if (isinstance(node.func, ast.Attribute) and node.func.attr == 'Decimal'
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in decimal_modules):
            real_decimal_call = True
    assert real_decimal_call, 'aggregator.py must import and actually call decimal.Decimal'

    behavioral = tmp_path / 'check_aggregator.py'
    behavioral.write_text(r'''
import importlib.util
import random
from decimal import Decimal, ROUND_HALF_EVEN, localcontext
from pathlib import Path

path = Path('/home/user/pipeline/aggregator.py')
spec = importlib.util.spec_from_file_location('submitted_aggregator', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
aggregate = module.aggregate_prices

def expected(values):
    with localcontext() as ctx:
        ctx.prec = 80
        ctx.rounding = ROUND_HALF_EVEN
        total = sum((Decimal(str(value)) for value in values), Decimal(0))
        return format(total, '.2f')

cases = [
    [],
    [2.675],
    [0.1] * 10,
    [0.01] * 10000,
    [10**16, 1.0, -(10**16)],
    [0.335, 0.335, 0.335],
    [-2.675],
    [123456789.125, 0.005, -123456789.0],
]
rng = random.Random(913731)
for _ in range(50):
    values = [float(f'{rng.randint(-900000, 900000) / 1000:.3f}') for _ in range(rng.randint(1, 250))]
    cases.append(values)

for index, values in enumerate(cases):
    got = aggregate(values)
    want = expected(values)
    if type(got) is not str:
        raise AssertionError(f'case {index}: returned {type(got).__name__}, not str')
    if got != want:
        raise AssertionError(f'case {index}: got {got!r}, want {want!r}')
''')
    result = run(['python3', str(behavioral)], cwd=PIPELINE, timeout=30)
    assert_ok(result, 'hidden Python decimal behavioral tests')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
