#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import shutil
import secrets
import random

PROJECT = '/home/user/project'
DEPS = os.path.join(PROJECT, 'build.deps')
CPP = os.path.join(PROJECT, 'cycle_detector.cpp')
LOG = os.path.join(PROJECT, 'cycle.log')
PIPELINE = os.path.join(PROJECT, 'ci_pipeline.sh')


def test_cycle_log_content():
    """Check if cycle.log contains the correct cycle."""
    assert os.path.isfile(LOG), f"{LOG} is missing."
    with open(LOG, 'r') as f:
        content = f.read().strip()
    expected_cycle = "Cycle: Core -> Utils -> Network -> Core"
    assert expected_cycle in content, f"Expected '{expected_cycle}' in {LOG}, got: {content}"


def test_build_deps_fixed():
    """Check that only the required Utils -> Network edge was removed."""
    assert os.path.isfile(DEPS), f"{DEPS} is missing."
    with open(DEPS, 'r') as f:
        content = f.read()

    # Preserve the original assertion.
    for line in content.splitlines():
        if line.strip().startswith('Utils'):
            if '->' in line:
                deps = line.split('->')[1]
                assert 'Network' not in deps, f"Circular dependency 'Network' still found in Utils dependencies: {line}"

    parsed = {}
    for raw in content.splitlines():
        if not raw.strip():
            continue
        assert '->' in raw, f"Malformed dependency line: {raw}"
        left, right = raw.split('->', 1)
        module = left.strip()
        assert module and module not in parsed, f"Invalid or duplicate module line: {raw}"
        parsed[module] = [x.strip() for x in right.split(',') if x.strip()]

    expected = {
        'Core': ['Utils', 'Math'],
        'Math': ['Utils'],
        'Network': ['Core', 'Crypto'],
        'Crypto': ['Utils'],
        'App': ['Network', 'UI'],
        'UI': ['Core'],
    }
    for module, dependencies in expected.items():
        assert parsed.get(module) == dependencies, f"Unexpected dependencies for {module}: {parsed.get(module)}"
    assert set(parsed) <= set(expected) | {'Utils'}, f"Unexpected modules in fixed graph: {set(parsed) - set(expected) - {'Utils'}}"
    if 'Utils' in parsed:
        assert parsed['Utils'] == [], f"Utils should have no dependencies, got {parsed['Utils']}"


def test_cpp_file_exists():
    """Check if cycle_detector.cpp exists and can be compiled."""
    assert os.path.isfile(CPP), f"{CPP} is missing."
    output = os.path.join(tempfile.gettempdir(), 'detector_test_' + secrets.token_hex(8))
    result = subprocess.run(
        ['g++', '-std=c++17', CPP, '-o', output],
        cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"cycle_detector.cpp did not compile:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    os.unlink(output)


def test_ci_pipeline_exists_and_executable():
    """Check if ci_pipeline.sh exists, is executable, and names the required artifacts."""
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    st = os.stat(PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PIPELINE} is not executable."
    with open(PIPELINE, 'r') as f:
        script = f.read()
    assert 'cycle_detector.cpp' in script, "Pipeline does not reference cycle_detector.cpp"
    assert 'detector' in script, "Pipeline does not produce/run detector"
    assert 'build.deps' in script, "Pipeline does not pass build.deps"
    assert ('g++' in script or 'c++' in script), "Pipeline does not invoke a C++ compiler"


def test_ci_pipeline_execution():
    """Run ci_pipeline.sh on the fixed graph and the original broken graph."""
    with open(DEPS, 'rb') as f:
        fixed_data = f.read()
    old_log = open(LOG, 'rb').read() if os.path.isfile(LOG) else None

    # A real pipeline must replace this poisoned detector by compiling the source.
    with open(os.path.join(PROJECT, 'detector'), 'w') as f:
        f.write('#!/bin/sh\nexit 77\n')
    os.chmod(os.path.join(PROJECT, 'detector'), 0o755)

    try:
        result_fixed = subprocess.run([PIPELINE], cwd=PROJECT, capture_output=True, timeout=30)
        assert result_fixed.returncode == 0, f"{PIPELINE} failed on fixed build.deps. Output: {result_fixed.stderr.decode(errors='replace')}"
        detector = os.path.join(PROJECT, 'detector')
        assert os.path.isfile(detector) and os.access(detector, os.X_OK), "Pipeline did not create an executable detector"
        with open(detector, 'rb') as f:
            assert f.read(4) == b'\x7fELF', "Pipeline did not compile detector as a C++ executable"

        broken_deps = """Core -> Utils, Math
Math -> Utils
Network -> Core, Crypto
Crypto -> Utils
App -> Network, UI
UI -> Core
Utils -> Network
"""
        with open(DEPS, 'w') as f:
            f.write(broken_deps)
        result_broken = subprocess.run([PIPELINE], cwd=PROJECT, capture_output=True, timeout=30)
        assert result_broken.returncode == 1, f"{PIPELINE} should have exited with 1 on broken build.deps, got {result_broken.returncode}."
    finally:
        with open(DEPS, 'wb') as f:
            f.write(fixed_data)
        if old_log is None:
            if os.path.exists(LOG):
                os.unlink(LOG)
        else:
            with open(LOG, 'wb') as f:
                f.write(old_log)


def test_detector_on_unseen_graphs_and_whitespace():
    """Compile the submitted C++ and exercise it on unpredictable DAGs and cycles."""
    with open(DEPS, 'rb') as f:
        fixed_data = f.read()
    old_log = open(LOG, 'rb').read() if os.path.isfile(LOG) else None
    binary = os.path.join(tempfile.gettempdir(), 'detector_dynamic_' + secrets.token_hex(8))

    compiled = subprocess.run(
        ['g++', '-std=c++17', CPP, '-o', binary],
        cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert compiled.returncode == 0, f"cycle_detector.cpp did not compile:\n{compiled.stderr}"

    token = secrets.token_hex(6).upper()
    a, m, z = 'A' + token, 'M' + token, 'Z' + token
    leaf, root = 'L' + token, 'R' + token

    cycle_lines = [
        f"\t{z}  ->   {a}   ",
        f" {m}-> {z}",
        f"{a} \t ->\t {m},  {leaf}",
        f"{leaf} ->   ",
        f"{root} -> {leaf}",
    ]
    random.SystemRandom().shuffle(cycle_lines)
    cycle_graph = '\n\n'.join(cycle_lines) + '\n'
    expected_cycle = f"Cycle: {a} -> {m} -> {z} -> {a}"

    dag_graph = f"""
      {root} -> {a}, {m}
    {a}-> {leaf}
    {m} -> {z}, {leaf}
    {z} ->
    {leaf} ->
    """
    self_node = 'S' + secrets.token_hex(6).upper()
    self_cycle = f"\n {self_node}  ->  {self_node}\n"

    try:
        for graph, expected_code, expected_log in [
            (dag_graph, 0, None),
            (cycle_graph, 1, expected_cycle),
            (self_cycle, 1, f"Cycle: {self_node} -> {self_node}"),
        ]:
            with open(DEPS, 'w') as f:
                f.write(graph)
            if os.path.exists(LOG):
                os.unlink(LOG)
            result = subprocess.run([binary, DEPS], cwd=PROJECT, capture_output=True, timeout=15)
            assert result.returncode == expected_code, (
                f"Detector returned {result.returncode}, expected {expected_code}, for graph:\n{graph}\n"
                f"stderr: {result.stderr.decode(errors='replace')}"
            )
            if expected_log is not None:
                assert os.path.isfile(LOG), "Detector found a cycle but did not create cycle.log"
                with open(LOG, 'r') as f:
                    actual = f.read().strip()
                assert actual == expected_log, f"Expected exact log '{expected_log}', got '{actual}'"
    finally:
        with open(DEPS, 'wb') as f:
            f.write(fixed_data)
        if old_log is None:
            if os.path.exists(LOG):
                os.unlink(LOG)
        else:
            with open(LOG, 'wb') as f:
                f.write(old_log)
        if os.path.exists(binary):
            os.unlink(binary)


def test_pipeline_on_unseen_graphs():
    """Ensure the pipeline uses the detector rather than recognizing the fixed audit graphs."""
    with open(DEPS, 'rb') as f:
        fixed_data = f.read()
    old_log = open(LOG, 'rb').read() if os.path.isfile(LOG) else None
    token = secrets.token_hex(7).upper()
    a, b, c = 'A' + token, 'B' + token, 'C' + token
    cycle_graph = f"{c} -> {a}\n{a} -> {b}\n{b} -> {c}\n"
    dag_graph = f"{a} -> {b}, {c}\n{b} -> {c}\n{c} ->\n"

    try:
        with open(DEPS, 'w') as f:
            f.write(cycle_graph)
        result = subprocess.run([PIPELINE], cwd=PROJECT, capture_output=True, timeout=30)
        assert result.returncode == 1, f"Pipeline accepted an unseen cyclic graph; got {result.returncode}"
        with open(LOG, 'r') as f:
            assert f.read().strip() == f"Cycle: {a} -> {b} -> {c} -> {a}"

        with open(DEPS, 'w') as f:
            f.write(dag_graph)
        result = subprocess.run([PIPELINE], cwd=PROJECT, capture_output=True, timeout=30)
        assert result.returncode == 0, f"Pipeline rejected an unseen DAG; got {result.returncode}"
    finally:
        with open(DEPS, 'wb') as f:
            f.write(fixed_data)
        if old_log is None:
            if os.path.exists(LOG):
                os.unlink(LOG)
        else:
            with open(LOG, 'wb') as f:
                f.write(old_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
