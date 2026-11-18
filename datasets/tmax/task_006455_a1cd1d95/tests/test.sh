#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import itertools
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest
from packaging.specifiers import SpecifierSet
from packaging.version import Version

HOME = "/home/user"
RESOLVE = f"{HOME}/resolve.py"
BUILD_SH = f"{HOME}/build.sh"
MATRIX = f"{HOME}/environment_matrix.json"
RESOLVED = f"{HOME}/resolved_versions.json"

CANONICAL_MATRIX = {
    "packages": {
        "lib-alpha": {"versions": {
            "1.0.0": {}, "1.1.0": {}, "1.2.0": {}, "2.0.0": {}
        }},
        "lib-beta": {"versions": {
            "1.0.0": {"dependencies": {"lib-alpha": ">=1.0.0,<2.0.0"}},
            "2.0.0": {"dependencies": {"lib-alpha": ">=1.1.0,<2.0.0"}}
        }},
        "lib-gamma": {"versions": {
            "1.0.0": {"dependencies": {
                "lib-beta": ">=2.0.0,<3.0.0", "lib-alpha": "<1.2.0"
            }}
        }},
        "test-runner": {"versions": {
            "1.0.0": {"dependencies": {"lib-gamma": ">=1.0.0,<2.0.0"}}
        }}
    }
}

EXPECTED = {
    "test-runner": "1.0.0",
    "lib-gamma": "1.0.0",
    "lib-beta": "2.0.0",
    "lib-alpha": "1.1.0"
}

_resolver_prepared = False
_build_prepared = False


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f, indent=2)


def derive_resolution(matrix):
    packages = matrix["packages"]
    names = sorted(packages)
    valid = []
    version_lists = [list(packages[name]["versions"]) for name in names]

    for versions in itertools.product(*version_lists):
        chosen = dict(zip(names, versions))
        if chosen.get("test-runner") != "1.0.0":
            continue
        reachable = {"test-runner"}
        pending = ["test-runner"]
        ok = True
        while pending and ok:
            package = pending.pop()
            metadata = packages[package]["versions"][chosen[package]]
            for dependency, constraint in metadata.get("dependencies", {}).items():
                if dependency not in chosen or Version(chosen[dependency]) not in SpecifierSet(constraint):
                    ok = False
                    break
                if dependency not in reachable:
                    reachable.add(dependency)
                    pending.append(dependency)
        if ok:
            candidate = {name: chosen[name] for name in reachable}
            valid.append(candidate)

    assert valid, "Verifier-generated matrix unexpectedly has no solution"
    maximal = []
    for candidate in valid:
        dominated = False
        for other in valid:
            if candidate.keys() != other.keys():
                continue
            no_lower = all(Version(other[n]) >= Version(candidate[n]) for n in candidate)
            one_higher = any(Version(other[n]) > Version(candidate[n]) for n in candidate)
            if no_lower and one_higher:
                dominated = True
                break
        if not dominated:
            maximal.append(candidate)
    assert len(maximal) == 1, f"Generated matrix has ambiguous latest solution: {maximal}"
    return maximal[0]


def run_resolver(matrix):
    write_json(MATRIX, matrix)
    if os.path.exists(RESOLVED):
        os.remove(RESOLVED)
    result = subprocess.run(
        ["python3", RESOLVE], cwd=HOME, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, f"resolve.py failed: {result.stderr}"
    assert os.path.isfile(RESOLVED), "resolve.py did not create resolved_versions.json"
    try:
        with open(RESOLVED) as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"resolve.py produced invalid JSON: {exc}")


def prepare_resolver():
    global _resolver_prepared
    if _resolver_prepared:
        return
    assert os.path.isfile(RESOLVE), f"File {RESOLVE} is missing."

    nonce = secrets.randbelow(700) + 100
    variant = {
        "packages": {
            "lib-alpha": {"versions": {
                "1.0.0": {}, f"1.1.{nonce}": {}, f"1.5.{nonce}": {},
                f"1.9.{nonce}": {}, "2.0.0": {}
            }},
            "lib-beta": {"versions": {
                "1.0.0": {"dependencies": {"lib-alpha": ">=1.0.0,<2.0.0"}},
                f"2.4.{nonce}": {"dependencies": {
                    "lib-alpha": f">=1.1.{nonce},<1.9.{nonce}"
                }},
                f"2.8.{nonce}": {"dependencies": {
                    "lib-alpha": f">=1.9.{nonce},<2.0.0"
                }}
            }},
            "lib-gamma": {"versions": {
                f"1.3.{nonce}": {"dependencies": {
                    "lib-beta": ">=2.0.0,<3.0.0",
                    "lib-alpha": f"<1.9.{nonce}"
                }}
            }},
            "test-runner": {"versions": {
                "1.0.0": {"dependencies": {"lib-gamma": ">=1.0.0,<2.0.0"}}
            }}
        }
    }

    try:
        expected_variant = derive_resolution(variant)
        actual_variant = run_resolver(variant)
        assert actual_variant == expected_variant, (
            f"resolve.py failed a generated dependency matrix. "
            f"Expected {expected_variant}, got {actual_variant}"
        )
    finally:
        write_json(MATRIX, CANONICAL_MATRIX)

    actual = run_resolver(CANONICAL_MATRIX)
    assert actual == EXPECTED, f"Incorrect canonical resolution: got {actual}"
    _resolver_prepared = True


def prepare_build():
    global _build_prepared
    prepare_resolver()
    if _build_prepared:
        return
    assert os.path.isfile(BUILD_SH), f"File {BUILD_SH} is missing."
    shutil.rmtree(f"{HOME}/build", ignore_errors=True)
    result = subprocess.run(
        ["bash", BUILD_SH], cwd=HOME, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"build.sh failed: {result.stderr}"
    _build_prepared = True


def test_resolve_script_handles_generated_constraints():
    prepare_resolver()


def test_resolved_versions_json():
    prepare_resolver()
    assert os.path.exists(RESOLVED), f"File {RESOLVED} is missing."
    with open(RESOLVED) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESOLVED} is not a valid JSON.")
    assert data == EXPECTED, f"Content of {RESOLVED} does not match expected resolved versions. Got {data}"


def test_source_files_exist_and_implement_required_functions():
    prepare_resolver()
    src_files = [
        f"{HOME}/src/lib-alpha.c",
        f"{HOME}/src/lib-beta.c",
        f"{HOME}/src/lib-gamma.c",
        f"{HOME}/src/main.c"
    ]
    for path in src_files:
        assert os.path.exists(path), f"Source file {path} is missing."
        assert os.path.isfile(path), f"Source path {path} is not a regular file."

    with tempfile.TemporaryDirectory() as td:
        expected_functions = {
            "lib-alpha": "init_lib_alpha",
            "lib-beta": "init_lib_beta",
            "lib-gamma": "init_lib_gamma"
        }
        for package, function in expected_functions.items():
            output = os.path.join(td, package + ".so")
            result = subprocess.run(
                ["gcc", "-shared", "-fPIC", f"{HOME}/src/{package}.c", "-o", output],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            assert result.returncode == 0, f"Could not compile {package}.c: {result.stderr}"
            lib = ctypes.CDLL(output)
            assert hasattr(lib, function), f"{package}.c does not define {function}"
            getattr(lib, function)()

        trace = os.path.join(td, "trace.txt")
        tracker_objects = []
        for package, function in expected_functions.items():
            source = os.path.join(td, package + "-tracker.c")
            library = os.path.join(td, package + "-tracker.so")
            with open(source, "w") as f:
                f.write(
                    '#include <stdio.h>\n#include <stdlib.h>\n'
                    f'void {function}(void) {{ FILE *f = fopen(getenv("TRACE_FILE"), "a"); '
                    f'if (f) {{ fputs("{package}\\n", f); fclose(f); }} }}\n'
                )
            subprocess.run(["gcc", "-shared", "-fPIC", source, "-o", library], check=True)
            tracker_objects.append(library)

        runner = os.path.join(td, "runner")
        result = subprocess.run(
            ["gcc", "-O0", f"{HOME}/src/main.c", *tracker_objects, "-o", runner],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f"main.c does not link against the required init functions: {result.stderr}"
        env = os.environ.copy()
        env["TRACE_FILE"] = trace
        result = subprocess.run([runner], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert result.returncode == 0, f"Executable built from main.c failed: {result.stderr.decode()}"
        called = set()
        if os.path.exists(trace):
            with open(trace) as f:
                called = {line.strip() for line in f if line.strip()}
        assert called == set(expected_functions), f"main.c did not call every init function; observed {called}"


def test_compiled_shared_objects_exist():
    prepare_build()
    so_files = [
        f"{HOME}/build/lib-alpha-1.1.0.so",
        f"{HOME}/build/lib-beta-2.0.0.so",
        f"{HOME}/build/lib-gamma-1.0.0.so"
    ]
    functions = ["init_lib_alpha", "init_lib_beta", "init_lib_gamma"]
    for path, function in zip(so_files, functions):
        assert os.path.exists(path), f"Shared object file {path} is missing."
        lib = ctypes.CDLL(path)
        assert hasattr(lib, function), f"{path} does not export {function}"
        getattr(lib, function)()


def test_executable_exists_and_runs():
    prepare_build()
    exe_path = f"{HOME}/build/test-runner"
    assert os.path.exists(exe_path), f"Executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{HOME}/build" + (":" + env["LD_LIBRARY_PATH"] if "LD_LIBRARY_PATH" in env else "")
    result = subprocess.run([exe_path], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert result.returncode == 0, f"Running {exe_path} failed with exit code {result.returncode}. Stderr: {result.stderr.decode()}"


def test_executable_dynamic_linking():
    prepare_build()
    exe_path = f"{HOME}/build/test-runner"
    assert os.path.exists(exe_path), f"Executable {exe_path} is missing."
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{HOME}/build" + (":" + env["LD_LIBRARY_PATH"] if "LD_LIBRARY_PATH" in env else "")
    result = subprocess.run(
        ["ldd", exe_path], env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"ldd command failed on {exe_path}: {result.stderr}"
    expected_libs = ["lib-alpha-1.1.0.so", "lib-beta-2.0.0.so", "lib-gamma-1.0.0.so"]
    for lib in expected_libs:
        assert lib in result.stdout, f"Executable is not dynamically linked against {lib}. ldd output:\n{result.stdout}"

    nm = subprocess.run(
        ["nm", "-D", "--undefined-only", exe_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True
    ).stdout
    for function in ["init_lib_alpha", "init_lib_beta", "init_lib_gamma"]:
        assert function in nm, f"test-runner does not actually reference {function}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
