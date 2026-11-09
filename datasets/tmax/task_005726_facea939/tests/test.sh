#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import glob
import os
import shutil
import subprocess
import sys
import tempfile

import pytest

LIB_DIR = "/home/user/libs/bin"
PROJECT = "/home/user/project"
RESOLVER = "/home/user/resolve.py"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_shared_libraries_exist():
    """Test that the compiled shared libraries exist in the correct directory."""
    lib1 = "/home/user/libs/bin/libmagic_v1.1.5.so"
    lib2 = "/home/user/libs/bin/libmagic_v2.3.1.so"

    assert os.path.exists(lib1), f"Shared library missing: {lib1}"
    assert os.path.exists(lib2), f"Shared library missing: {lib2}"


def test_library_sources_and_shared_objects_are_real():
    expected = {
        "libmagic_v1.1.5.c": ("libmagic_v1.1.5.so", 42),
        "libmagic_v2.3.1.c": ("libmagic_v2.3.1.so", 99),
    }
    with tempfile.TemporaryDirectory() as td:
        for source_name, (library_name, value) in expected.items():
            source = os.path.join("/home/user/libs", source_name)
            installed = os.path.join(LIB_DIR, library_name)
            assert os.path.isfile(source), f"C source missing: {source}"
            assert os.path.isfile(installed), f"Shared library missing: {installed}"

            rebuilt = os.path.join(td, library_name)
            result = run(["gcc", "-shared", "-fPIC", source, "-o", rebuilt])
            assert result.returncode == 0, result.stderr

            for candidate in (rebuilt, installed):
                probe = run([
                    sys.executable,
                    "-c",
                    "import ctypes,sys; "
                    "lib=ctypes.CDLL(sys.argv[1]); "
                    "f=lib.get_magic_number; f.restype=ctypes.c_int; "
                    "print(f())",
                    candidate,
                ])
                assert probe.returncode == 0, probe.stderr
                assert probe.stdout.strip() == str(value)


def test_resolve_py_behavior():
    """Test that resolve.py correctly identifies the highest version >= minimum."""
    resolver_path = "/home/user/resolve.py"
    assert os.path.exists(resolver_path), f"Resolver script missing: {resolver_path}"

    target_dir = "/home/user/libs/bin"
    min_version = "2.0.0"

    result = subprocess.run(
        ["python3", resolver_path, target_dir, min_version],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"resolve.py failed with error: {result.stderr}"

    output = result.stdout.strip()
    expected_output = "/home/user/libs/bin/libmagic_v2.3.1.so"

    assert output == expected_output, f"resolve.py returned '{output}', expected '{expected_output}'"


def test_resolver_handles_unseen_version_sets():
    cases = [
        (["1.0.0", "2.0.0", "2.8.4", "10.0.0"], "2.0.0", "10.0.0"),
        (["0.9.9", "1.2.3", "1.10.0", "1.3.8"], "1.0.0", "1.10.0"),
        (["3.0.0", "3.0.1", "2.99.99"], "3.0.1", "3.0.1"),
    ]
    for versions, minimum, expected in cases:
        with tempfile.TemporaryDirectory() as td:
            for version in versions:
                open(os.path.join(td, f"libmagic_v{version}.so"), "wb").close()
            open(os.path.join(td, "unrelated.so"), "wb").close()
            result = run([sys.executable, RESOLVER, td, minimum])
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == os.path.join(td, f"libmagic_v{expected}.so")
            assert len(result.stdout.strip().splitlines()) == 1


def test_setup_builds_and_links_real_extension_via_resolver():
    setup_py = os.path.join(PROJECT, "setup.py")
    extension_source = os.path.join(PROJECT, "magic_ext.c")
    assert os.path.isfile(setup_py), f"Build script missing: {setup_py}"
    assert os.path.isfile(extension_source), f"Extension source missing: {extension_source}"

    for path in glob.glob(os.path.join(PROJECT, "magic_ext*.so")):
        os.remove(path)
    shutil.rmtree(os.path.join(PROJECT, "build"), ignore_errors=True)

    backup = "/tmp/resolve_agent_original.py"
    marker = "/tmp/resolve_invocations.txt"
    shutil.copy2(RESOLVER, backup)
    if os.path.exists(marker):
        os.remove(marker)
    wrapper = '''#!/usr/bin/env python3
import os, sys
with open("/tmp/resolve_invocations.txt", "a") as f:
    f.write(repr(sys.argv[1:]) + "\\n")
os.execv(sys.executable, [sys.executable, "/tmp/resolve_agent_original.py"] + sys.argv[1:])
'''
    try:
        with open(RESOLVER, "w") as f:
            f.write(wrapper)
        os.chmod(RESOLVER, 0o755)
        build = run([sys.executable, "setup.py", "build_ext", "--inplace"], cwd=PROJECT)
    finally:
        shutil.copy2(backup, RESOLVER)

    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(marker), "setup.py did not invoke /home/user/resolve.py"
    with open(marker) as f:
        invocations = f.read()
    assert repr([LIB_DIR, "2.0.0"]) in invocations, invocations

    built = glob.glob(os.path.join(PROJECT, "magic_ext*.so"))
    assert len(built) == 1, f"Expected one in-place extension, found: {built}"
    extension = built[0]

    file_info = run(["file", extension])
    assert file_info.returncode == 0 and "shared object" in file_info.stdout.lower()

    symbols = run(["nm", "-D", extension])
    assert symbols.returncode == 0, symbols.stderr
    assert any(" U get_magic_number" in line for line in symbols.stdout.splitlines()), symbols.stdout

    dynamic = run(["readelf", "-d", extension])
    assert dynamic.returncode == 0, dynamic.stderr
    assert "libmagic_v2.3.1.so" in dynamic.stdout, dynamic.stdout
    assert "libmagic_v1.1.5.so" not in dynamic.stdout, dynamic.stdout

    dependencies = run(["ldd", extension])
    assert dependencies.returncode == 0, dependencies.stderr
    assert "/home/user/libs/bin/libmagic_v2.3.1.so" in dependencies.stdout, dependencies.stdout

    imported = run([
        sys.executable,
        "-c",
        "import magic_ext; print(magic_ext.get_value())",
    ], cwd=PROJECT)
    assert imported.returncode == 0, imported.stderr
    assert imported.stdout.strip() == "99"


def test_e2e_script_really_exercises_extension_and_writes_log():
    script = os.path.join(PROJECT, "test_e2e.py")
    assert os.path.isfile(script), f"End-to-end script missing: {script}"
    with open(script) as f:
        tree = ast.parse(f.read(), filename=script)

    imports_magic = any(
        (isinstance(node, ast.Import) and any(alias.name == "magic_ext" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "magic_ext")
        for node in ast.walk(tree)
    )
    calls_get_value = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "get_value"
        for node in ast.walk(tree)
    )
    has_assert = any(isinstance(node, ast.Assert) for node in ast.walk(tree))
    has_99 = any(isinstance(node, ast.Constant) and node.value == 99 for node in ast.walk(tree))
    assert imports_magic and calls_get_value and has_assert and has_99

    log_path = "/home/user/result.log"
    if os.path.exists(log_path):
        os.remove(log_path)
    result = run([sys.executable, script], cwd=PROJECT)
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(log_path), f"Result log missing after running {script}"
    with open(log_path, "rb") as f:
        assert f.read() == b"E2E SUCCESS: 99"


def test_e2e_result_log():
    """Test that the end-to-end test ran successfully and produced the correct log."""
    log_path = "/home/user/result.log"
    assert os.path.exists(log_path), f"Result log missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "E2E SUCCESS: 99"
    assert content == expected_content, f"result.log contains '{content}', expected '{expected_content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
