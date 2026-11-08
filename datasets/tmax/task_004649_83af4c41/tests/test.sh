#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

DEPLOY_DIR = "/home/user/deploy"


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", DEPLOY_DIR)
    kwargs.setdefault("text", True)
    kwargs.setdefault("stdout", subprocess.PIPE)
    kwargs.setdefault("stderr", subprocess.STDOUT)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, **kwargs)


def needed_entries(path):
    proc = run(["/usr/bin/readelf", "-d", path])
    assert proc.returncode == 0, f"readelf failed on {path}:\n{proc.stdout}"
    return re.findall(r"\(NEEDED\).*?Shared library: \[(.*?)\]", proc.stdout)


def expected_local_graph():
    graph = {}
    pending = ["math_engine"]
    while pending:
        name = pending.pop()
        if name in graph:
            continue
        path = os.path.join(DEPLOY_DIR, name)
        assert os.path.isfile(path), f"Expected local ELF {path} is missing"
        local = []
        for dependency in needed_entries(path):
            dependency_name = os.path.basename(dependency)
            if os.path.isfile(os.path.join(DEPLOY_DIR, dependency_name)):
                local.append(dependency_name)
                if dependency_name not in graph:
                    pending.append(dependency_name)
        graph[name] = local
    return graph


def load_graph():
    deps_file = os.path.join(DEPLOY_DIR, "deps.json")
    assert os.path.isfile(deps_file), f"{deps_file} does not exist."
    try:
        with open(deps_file, "r") as f:
            deps = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{deps_file} is not valid JSON.")
    assert isinstance(deps, dict), "deps.json should contain a dictionary."
    for key, value in deps.items():
        assert isinstance(key, str), "Dependency graph keys must be filenames"
        assert isinstance(value, list), f"Dependencies for {key} must be a list"
        assert all(isinstance(item, str) for item in value), f"Dependencies for {key} must be filenames"
        assert len(value) == len(set(value)), f"Dependencies for {key} contain duplicates"
    return deps


def assert_graph_matches_elf(deps):
    expected = expected_local_graph()
    assert set(deps) == set(expected), f"Graph keys differ from recursively reachable local ELFs: expected {expected}, got {deps}"
    for name in expected:
        assert set(deps[name]) == set(expected[name]), f"Wrong direct local dependencies for {name}: expected {expected[name]}, got {deps[name]}"


def execute_analyzer():
    script = os.path.join(DEPLOY_DIR, "analyze_deps.py")
    assert os.path.isfile(script), f"{script} does not exist."
    deps_file = os.path.join(DEPLOY_DIR, "deps.json")
    if os.path.exists(deps_file):
        os.unlink(deps_file)
    proc = run(["/usr/bin/python3", script])
    assert proc.returncode == 0, f"analyze_deps.py failed:\n{proc.stdout}"
    return load_graph()


def test_analyze_deps_executes_and_resolves_dynamic_graph():
    core = os.path.join(DEPLOY_DIR, "libcore.so")
    magic = os.path.join(DEPLOY_DIR, "libmagic.so")
    assert os.path.isfile(core)
    assert os.path.isfile(magic)

    probe_name = f"libaudit_probe_{uuid.uuid4().hex}.so"
    probe = os.path.join(DEPLOY_DIR, probe_name)
    fd, backup = tempfile.mkstemp(prefix="libcore-audit-", suffix=".so")
    os.close(fd)
    shutil.copy2(core, backup)
    shutil.copy2(magic, probe)
    try:
        patch = run(["/usr/bin/patchelf", "--add-needed", probe_name, core])
        assert patch.returncode == 0, f"Could not create analyzer probe graph:\n{patch.stdout}"
        probed = execute_analyzer()
        assert_graph_matches_elf(probed)
        assert probe_name in probed["libcore.so"], "Analyzer ignored a newly added direct local dependency"
        assert probe_name in probed, "Analyzer did not recursively visit a newly added local library"
    finally:
        shutil.copy2(backup, core)
        os.unlink(backup)
        if os.path.exists(probe):
            os.unlink(probe)

    deps = execute_analyzer()
    assert_graph_matches_elf(deps)

    # Preserve the original dependency assertions.
    assert "math_engine" in deps, "math_engine missing from deps.json"
    assert "libcore.so" in deps["math_engine"], "math_engine should depend on libcore.so"
    assert "libcore.so" in deps, "libcore.so missing from deps.json"
    assert "libmath_ops.so" in deps["libcore.so"], "libcore.so should depend on libmath_ops.so"
    assert "libmath_ops.so" in deps, "libmath_ops.so missing from deps.json"
    assert "liblegacy.so" in deps["libmath_ops.so"] or "libmagic.so" in deps["libmath_ops.so"], \
        "libmath_ops.so should depend on liblegacy.so or libmagic.so in deps.json"


def test_magic_assembly_and_library_behavior():
    magic_s = os.path.join(DEPLOY_DIR, "magic.s")
    libmagic = os.path.join(DEPLOY_DIR, "libmagic.so")
    assert os.path.isfile(magic_s), f"{magic_s} does not exist."
    assert os.path.isfile(libmagic), f"{libmagic} does not exist."

    header = run(["/usr/bin/readelf", "-h", libmagic])
    assert header.returncode == 0, f"libmagic.so is not a readable ELF file:\n{header.stdout}"
    assert re.search(r"Type:\s+DYN", header.stdout), "libmagic.so is not a shared ELF object"

    built = os.path.join(tempfile.mkdtemp(prefix="magic-audit-"), "libmagic-from-source.so")
    try:
        compile_result = run(["/usr/bin/gcc", "-shared", "-fPIC", magic_s, "-o", built])
        assert compile_result.returncode == 0, f"magic.s cannot be assembled into a shared library:\n{compile_result.stdout}"

        for candidate in (libmagic, built):
            library = ctypes.CDLL(candidate)
            try:
                function = library.calculate_magic_constant
            except AttributeError:
                pytest.fail(f"{candidate} does not export calculate_magic_constant")
            function.argtypes = []
            function.restype = ctypes.c_int
            assert function() == 42, f"calculate_magic_constant in {candidate} did not return 42"
    finally:
        shutil.rmtree(os.path.dirname(built), ignore_errors=True)


def test_libmath_ops_linkage():
    libmath_ops = os.path.join(DEPLOY_DIR, "libmath_ops.so")
    assert os.path.isfile(libmath_ops), f"{libmath_ops} does not exist."
    output = run(["/usr/bin/readelf", "-d", libmath_ops])
    assert output.returncode == 0, f"readelf failed on {libmath_ops}:\n{output.stdout}"
    assert "libmagic.so" in output.stdout, f"libmath_ops.so does not have a NEEDED entry for libmagic.so. Output:\n{output.stdout}"
    assert "liblegacy.so" not in output.stdout, f"libmath_ops.so still has a NEEDED entry for liblegacy.so. Output:\n{output.stdout}"


def test_run_deployment_executes_engine_and_produces_real_result():
    script = os.path.join(DEPLOY_DIR, "run_deployment.sh")
    engine = os.path.join(DEPLOY_DIR, "math_engine")
    result_file = os.path.join(DEPLOY_DIR, "result.txt")
    assert os.path.isfile(script), f"{script} does not exist."
    assert os.path.isfile(engine), f"{engine} does not exist."

    fd, backup = tempfile.mkstemp(prefix="math-engine-audit-")
    os.close(fd)
    shutil.copy2(engine, backup)
    marker = "deployment-probe-" + uuid.uuid4().hex
    wrapper = f'''#!/bin/sh
case ":${{LD_LIBRARY_PATH:-}}:" in
  *:/home/user/deploy:*|*:.:*|*:$PWD:*) printf '%s\\n' '{marker}' ;;
  *) echo 'LD_LIBRARY_PATH does not include the deployment directory' >&2; exit 73 ;;
esac
'''
    try:
        with open(engine, "w") as f:
            f.write(wrapper)
        os.chmod(engine, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                         stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        if os.path.exists(result_file):
            os.unlink(result_file)
        probe_run = run(["/bin/bash", script])
        assert probe_run.returncode == 0, f"run_deployment.sh failed its execution probe:\n{probe_run.stdout}"
        assert os.path.isfile(result_file), "run_deployment.sh did not create result.txt"
        with open(result_file) as f:
            assert f.read().strip() == marker, "run_deployment.sh did not execute ./math_engine and capture its output"
    finally:
        shutil.copy2(backup, engine)
        os.unlink(backup)

    if os.path.exists(result_file):
        os.unlink(result_file)
    deployment = run(["/bin/bash", script])
    assert deployment.returncode == 0, f"run_deployment.sh failed with the real engine:\n{deployment.stdout}"
    assert os.path.isfile(result_file), f"{result_file} does not exist."
    with open(result_file, "r") as f:
        res = f.read().strip()
    assert res == "Result: 94", f"Expected 'Result: 94' in result.txt, but got '{res}'"

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = DEPLOY_DIR
    direct = run([engine], env=env)
    assert direct.returncode == 0, f"Patched math_engine failed:\n{direct.stdout}"
    assert direct.stdout.strip() == "Result: 94", f"Patched math_engine produced unexpected output: {direct.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
