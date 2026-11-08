#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import shutil
import subprocess
import sys
import zipfile

import pytest

PROJECT = "/home/user/release_prep"
EXT_TARGET = "/tmp/verifier_rust_ext"


@pytest.fixture(scope="session", autouse=True)
def build_current_rust_extension():
    """Build and import the extension from the submitted Rust source."""
    wheel_dir = "/tmp/verifier_wheels"
    shutil.rmtree(wheel_dir, ignore_errors=True)
    shutil.rmtree(EXT_TARGET, ignore_errors=True)
    os.makedirs(wheel_dir)
    os.makedirs(EXT_TARGET)

    proc = subprocess.run(
        [
            "maturin", "build", "--release",
            "--manifest-path", os.path.join(PROJECT, "rust_ext", "Cargo.toml"),
            "--out", wheel_dir,
        ],
        cwd=os.path.join(PROJECT, "rust_ext"),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=360,
    )
    assert proc.returncode == 0, "Rust extension did not compile:\n" + proc.stdout

    wheels = glob.glob(os.path.join(wheel_dir, "*.whl"))
    assert wheels, "maturin did not produce a wheel"
    with zipfile.ZipFile(wheels[-1]) as wheel:
        wheel.extractall(EXT_TARGET)

    native_files = glob.glob(os.path.join(EXT_TARGET, "**", "rust_ext*.so"), recursive=True)
    assert native_files, "Built wheel does not contain a native rust_ext shared library"

    probe = r'''
import json
import math
import rust_ext
assert rust_ext.__file__.endswith(('.so', '.pyd')), rust_ext.__file__
cases = [
    ([1.0], 2.0),
    ([3.25, -4.5, 0.0], 1.75),
    ([-10.0, 2.5, 8.125, -0.25], 0.4),
    ([0.125, 999.0], 9.5),
]
for values, factor in cases:
    got = rust_ext.scale_and_append(values, factor)
    expected = [x * factor for x in values + [values[0] * factor]]
    assert len(got) == len(expected), (values, factor, got, expected)
    assert all(math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12)
               for a, b in zip(got, expected)), (values, factor, got, expected)
assert rust_ext.scale_and_append([], 3.0) == []
'''
    env = os.environ.copy()
    env["PYTHONPATH"] = EXT_TARGET + os.pathsep + PROJECT
    run = subprocess.run(
        [sys.executable, "-c", probe], cwd="/tmp", env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    assert run.returncode == 0, "Freshly built extension failed behavioral tests:\n" + run.stdout


def verifier_env():
    env = os.environ.copy()
    env["PYTHONPATH"] = EXT_TARGET + os.pathsep + PROJECT
    return env


def test_deploy_report_generated_correctly():
    report_path = "/home/user/release_prep/deploy_report.json"
    assert os.path.isfile(report_path), f"Deployment report not found at {report_path}"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON")

    assert "status" in data, "Key 'status' missing from deploy_report.json"
    assert data["status"] == "success", f"Expected status 'success', got {data['status']}"

    assert "processed_metrics" in data, "Key 'processed_metrics' missing from deploy_report.json"
    metrics = data["processed_metrics"]

    # Expected logic:
    # original = [10.5, 20.1, 5.0, 8.2]
    # factor = 2.5
    # appended = original + [original[0] * factor]
    # result = [x * factor for x in appended]
    original = [10.5, 20.1, 5.0, 8.2]
    factor = 2.5
    appended = original + [original[0] * factor]
    expected = [x * factor for x in appended]

    assert len(metrics) == len(expected), f"Expected {len(expected)} metrics, got {len(metrics)}"

    for m, e in zip(metrics, expected):
        assert abs(m - e) < 1e-5, f"Mismatch in processed metrics: expected {e}, got {m}"


def test_test_runner_hypothesis_test():
    test_runner_path = "/home/user/release_prep/test_runner.py"
    assert os.path.isfile(test_runner_path), f"Test runner not found at {test_runner_path}"

    with open(test_runner_path, "r") as f:
        content = f.read()

    assert "hypothesis" in content, "The 'hypothesis' library is not imported or used in test_runner.py"
    assert "test_scale_property" in content, "The function 'test_scale_property' is missing in test_runner.py"
    assert "@given" in content, "The '@given' decorator from hypothesis is missing in test_runner.py"

    tree = ast.parse(content, filename=test_runner_path)
    funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "test_scale_property"]
    assert len(funcs) == 1, "test_scale_property must be a real top-level test function"
    fn = funcs[0]
    given_calls = [d for d in fn.decorator_list if isinstance(d, ast.Call) and
                   ((isinstance(d.func, ast.Name) and d.func.id == "given") or
                    (isinstance(d.func, ast.Attribute) and d.func.attr == "given"))]
    assert given_calls, "test_scale_property is not decorated with @given"
    given_call = given_calls[0]
    assert len(given_call.args) == 2, "@given must provide the list and factor strategies"

    def is_st_call(node, name):
        return isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == name

    def kw_literal(call, name):
        for kw in call.keywords:
            if kw.arg == name:
                return ast.literal_eval(kw.value)
        raise AssertionError(f"Missing {name} in {ast.unparse(call)}")

    list_strategy, factor_strategy = given_call.args
    assert is_st_call(list_strategy, "lists") and list_strategy.args, "First strategy must be st.lists(...)"
    element_strategy = list_strategy.args[0]
    assert is_st_call(element_strategy, "floats"), "List elements must use st.floats(...)"
    assert kw_literal(element_strategy, "min_value") == -1000
    assert kw_literal(element_strategy, "max_value") == 1000
    assert kw_literal(list_strategy, "min_size") == 1
    assert is_st_call(factor_strategy, "floats"), "Factor must use st.floats(...)"
    assert kw_literal(factor_strategy, "min_value") == 0.1
    assert kw_literal(factor_strategy, "max_value") == 10.0

    # Execute the submitted tests against the freshly compiled native extension.
    run = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", test_runner_path],
        cwd="/tmp", env=verifier_env(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180,
    )
    assert run.returncode == 0, "test_runner.py tests failed:\n" + run.stdout

    # The property must actually reject a scale_and_append implementation that
    # violates the required len(data) + 1 invariant.
    fault_probe = r'''
import sys
import types
import rust_ext

def bad_scale(data, factor):
    return list(data)

rust_ext.scale_and_append = bad_scale
import test_runner
test_runner.rust_ext = types.SimpleNamespace(scale_and_append=bad_scale)
test_runner.scale_and_append = bad_scale
try:
    test_runner.test_scale_property()
except AssertionError:
    sys.exit(0)
except BaseException as exc:
    print(type(exc).__name__, exc)
    sys.exit(2)
else:
    print('Property test accepted an implementation returning the wrong length')
    sys.exit(3)
'''
    probe = subprocess.run(
        [sys.executable, "-c", fault_probe], cwd="/tmp", env=verifier_env(),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180,
    )
    assert probe.returncode == 0, "Property test does not enforce the length invariant:\n" + probe.stdout


def test_test_runner_import_order_fixed():
    test_runner_path = "/home/user/release_prep/test_runner.py"
    assert os.path.isfile(test_runner_path), f"Test runner not found at {test_runner_path}"

    with open(test_runner_path, "r") as f:
        content = f.read()

    idx_ci_logger = content.find("ci_logger.init_logger()")
    idx_rust_ext = content.find("import rust_ext")

    if idx_ci_logger != -1 and idx_rust_ext != -1:
        assert idx_rust_ext < idx_ci_logger, "Import order bug not fixed: rust_ext must be imported before ci_logger.init_logger() is called."

    run = subprocess.run(
        [sys.executable, test_runner_path], cwd="/tmp", env=verifier_env(),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
    )
    assert run.returncode == 0, "test_runner.py still fails when executed:\n" + run.stdout
    assert "FATAL ERROR" not in run.stdout, "Import-order initialization failure still occurs"


def test_rust_borrow_checker_fixed():
    lib_rs_path = "/home/user/release_prep/rust_ext/src/lib.rs"
    assert os.path.isfile(lib_rs_path), f"Rust source not found at {lib_rs_path}"

    with open(lib_rs_path, "r") as f:
        content = f.read()

    # The bug was `let first = &values[0]; values.push(*first * factor);`
    # A valid fix usually involves copying or cloning, e.g., `let first = values[0];`
    assert "let first = &values[0];\n    values.push(*first * factor);" not in content, "The borrow checker bug in lib.rs is still present."


def test_generate_report_executes_on_input_data():
    script_path = os.path.join(PROJECT, "generate_report.py")
    data_path = os.path.join(PROJECT, "ci_data.json")
    report_path = os.path.join(PROJECT, "deploy_report.json")
    assert os.path.isfile(script_path), f"Report generator not found at {script_path}"

    with open(script_path, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=script_path)
    imports_rust = any(
        (isinstance(n, ast.Import) and any(a.name == "rust_ext" for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module == "rust_ext")
        for n in ast.walk(tree)
    )
    calls_scale = any(
        isinstance(n, ast.Call) and
        ((isinstance(n.func, ast.Attribute) and n.func.attr == "scale_and_append") or
         (isinstance(n.func, ast.Name) and n.func.id == "scale_and_append"))
        for n in ast.walk(tree)
    )
    assert imports_rust, "generate_report.py must import rust_ext"
    assert calls_scale, "generate_report.py must call rust_ext.scale_and_append"

    with open(data_path, "rb") as f:
        original_data = f.read()

    def run_generator():
        if os.path.exists(report_path):
            os.remove(report_path)
        proc = subprocess.run(
            [sys.executable, script_path], cwd="/tmp", env=verifier_env(),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
        )
        assert proc.returncode == 0, "generate_report.py failed:\n" + proc.stdout
        assert os.path.isfile(report_path), "generate_report.py did not create deploy_report.json"
        with open(report_path) as f:
            return json.load(f)

    try:
        dynamic_values = [3.25, -4.0, 0.125, 11.75, -8.5, 2.0]
        with open(data_path, "w") as f:
            json.dump({"project": "num_cruncher", "raw_metrics": dynamic_values}, f)
        report = run_generator()
        expected = [x * 2.5 for x in dynamic_values + [dynamic_values[0] * 2.5]]
        assert report.get("status") == "success"
        got = report.get("processed_metrics")
        assert isinstance(got, list) and len(got) == len(expected)
        assert all(abs(a - b) < 1e-9 for a, b in zip(got, expected)), (got, expected)
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)

    # Regenerate and leave the required final report for the original fixture.
    final_report = run_generator()
    original = json.loads(original_data.decode("utf-8"))["raw_metrics"]
    expected = [x * 2.5 for x in original + [original[0] * 2.5]]
    assert final_report == {"status": "success", "processed_metrics": expected}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
