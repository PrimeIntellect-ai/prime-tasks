#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import re
import subprocess
import uuid
from pathlib import Path

import pytest


def test_registry_json_updated():
    registry_path = '/home/user/project_root/config/registry.json'
    assert os.path.isfile(registry_path), f"File {registry_path} is missing."

    with open(registry_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{registry_path} is not valid JSON.")

    assert "components" in data, "Key 'components' missing in registry.json"
    components = data["components"]

    # Check removed components
    assert "Network" not in components, "'Network' component was not removed from registry.json."
    assert "PhysicsEngine" not in components, "'PhysicsEngine' component was not removed from registry.json."

    # Check remaining components
    assert components.get("Logger") == "logger.cpp", "'Logger' component is missing or incorrect in registry.json."
    assert components.get("Database") == "db.cpp", "'Database' component is missing or incorrect in registry.json."
    assert components.get("Renderer") == "render.cpp", "'Renderer' component is missing or incorrect in registry.json."


def test_license_headers_updated():
    files_to_check = [
        '/home/user/project_root/src/core/logger.cpp',
        '/home/user/project_root/src/backend/db.cpp',
        '/home/user/project_root/src/frontend/render.cpp'
    ]

    for path in files_to_check:
        assert os.path.isfile(path), f"File {path} is missing."
        with open(path, 'r') as f:
            content = f.read()

        assert "/* LICENSE_UPDATED_2024 */" in content, f"License header not updated correctly in {path}."
        assert "/* TODO: UPDATE_LICENSE */" not in content, f"Old license header still present in {path}."


def test_final_manifest_csv():
    manifest_path = '/home/user/workspace/final_manifest.csv'
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing. Did you run the C++ program and redirect its output?"

    expected_rows = [
        ['Component', 'Filename', 'AbsolutePath'],
        ['Database', 'db.cpp', '/home/user/project_root/src/backend/db.cpp'],
        ['Logger', 'logger.cpp', '/home/user/project_root/src/core/logger.cpp'],
        ['Renderer', 'render.cpp', '/home/user/project_root/src/frontend/render.cpp']
    ]

    actual_rows = []
    with open(manifest_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_rows.append(row)

    assert len(actual_rows) > 0, f"Manifest file {manifest_path} is empty."
    assert actual_rows[0] == expected_rows[0], f"CSV header is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}"
    assert actual_rows == expected_rows, f"CSV content does not match expected output or is not sorted correctly. Expected:\n{expected_rows}\nGot:\n{actual_rows}"


def test_cpp_program_exists():
    cpp_path = '/home/user/workspace/build_manifest.cpp'
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."


def test_cpp_program_compiles_and_generates_manifest_dynamically(tmp_path):
    cpp_path = Path('/home/user/workspace/build_manifest.cpp')
    registry_path = Path('/home/user/project_root/config/registry.json')
    src_root = Path('/home/user/project_root/src')
    manifest_path = Path('/home/user/workspace/final_manifest.csv')

    source = cpp_path.read_text()
    assert re.search(r'^\s*#\s*include\s*[<\"][^>\"]*json\.hpp[>\"]', source, re.MULTILINE), \
        "build_manifest.cpp must include the provided json.hpp header."
    assert re.search(r'\bnlohmann\s*::\s*json\b', source), \
        "build_manifest.cpp must use the nlohmann JSON library."

    executable = tmp_path / 'build_manifest'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-I/home/user/libs', str(cpp_path), '-o', str(executable)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, \
        f"build_manifest.cpp did not compile with -std=c++17:\n{compile_result.stderr}"

    baseline = subprocess.run(
        [str(executable)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15
    )
    assert baseline.returncode == 0, f"Compiled manifest generator failed:\n{baseline.stderr}"
    assert baseline.stdout == manifest_path.read_text(), \
        "The compiled generator's output does not match final_manifest.csv."

    original_registry = registry_path.read_bytes()
    probe_id = uuid.uuid4().hex
    probe_component = f"VerifierProbe_{probe_id}"
    probe_filename = f"probe_{probe_id}.cpp"
    probe_dir = src_root / f"verify_{probe_id}" / 'nested'
    probe_file = probe_dir / probe_filename

    try:
        registry = json.loads(original_registry.decode())
        registry['components'][probe_component] = probe_filename
        registry_path.write_text(json.dumps(registry, indent=2))
        probe_dir.mkdir(parents=True)
        probe_file.write_text('// verifier-generated discovery probe\n')

        run = subprocess.run(
            [str(executable)], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=15
        )
        assert run.returncode == 0, f"Generator failed on an updated registry:\n{run.stderr}"

        actual_rows = [row for row in csv.reader(io.StringIO(run.stdout)) if row]
        expected_rows = [['Component', 'Filename', 'AbsolutePath']]
        discovered = {}
        for path in src_root.rglob('*.cpp'):
            discovered.setdefault(path.name, []).append(str(path.resolve()))

        for component, filename in sorted(registry['components'].items()):
            matches = discovered.get(filename, [])
            assert len(matches) == 1, f"Verifier fixture expected exactly one source named {filename}."
            expected_rows.append([component, filename, matches[0]])

        assert actual_rows == expected_rows, \
            f"Generator did not derive the manifest from the updated registry and recursive source search. Expected:\n{expected_rows}\nGot:\n{actual_rows}"
        assert actual_rows[1:] == sorted(actual_rows[1:], key=lambda row: row[0]), \
            "Generated component rows are not sorted alphabetically."
        assert all(os.path.isabs(row[2]) for row in actual_rows[1:]), \
            "Every generated source path must be absolute."
    finally:
        registry_path.write_bytes(original_registry)
        if probe_file.exists():
            probe_file.unlink()
        current = probe_dir
        stop = src_root.resolve()
        while current.exists() and current.resolve() != stop:
            try:
                current.rmdir()
            except OSError:
                break
            current = current.parent
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
