#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import heapq
import os
import secrets
import stat
import subprocess


def test_build_script_exists_and_executable():
    script_path = "/home/user/build_all.sh"
    assert os.path.exists(script_path), f"The script {script_path} was not generated."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {script_path} is not executable."


def test_build_script_content():
    script_path = "/home/user/build_all.sh"
    assert os.path.exists(script_path), f"The script {script_path} was not generated."

    with open(script_path, "r") as f:
        content = f.read().strip()

    expected_content = """#!/bin/bash
echo "Building backend-go..."
cd /home/user/src/go-backend && make build
echo "Building cli-rust..."
cd /home/user/src/rust-cli && make build
echo "Building scripts-py..."
cd /home/user/src/py-scripts && make build
echo "Building aggregator-go..."
cd /home/user/src/go-agg && make build"""

    normalized_content = "\n".join(line.strip() for line in content.splitlines() if line.strip())
    normalized_expected = "\n".join(line.strip() for line in expected_content.splitlines() if line.strip())

    assert normalized_content == normalized_expected, "The generated build_all.sh does not match the expected content and topological order."


def test_orchestrate_script_exists():
    script_path = "/home/user/orchestrate.py"
    assert os.path.exists(script_path), f"The Python script {script_path} was not created."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def topological_order(components):
    by_name = {component["name"]: component for component in components}
    indegree = {name: 0 for name in by_name}
    dependents = {name: [] for name in by_name}

    for component in components:
        for dependency in component["deps"]:
            assert dependency in by_name
            indegree[component["name"]] += 1
            dependents[dependency].append(component["name"])

    ready = [name for name, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        name = heapq.heappop(ready)
        result.append(name)
        for dependent in dependents[name]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)

    assert len(result) == len(components)
    return result


def encode_manifest(components):
    blocks = []
    for component in components:
        deps = ", ".join(component["deps"]) if component["deps"] else "none"
        blocks.append(
            f'[Component: {component["name"]}]\n'
            f'Language: {component["language"]}\n'
            f'Path: {component["path"]}\n'
            f'Deps: {deps}'
        )
    text = "\n\n".join(blocks) + "\n"
    return base64.b64encode(text.encode("utf-16-le"))


def expected_script(components):
    by_name = {component["name"]: component for component in components}
    lines = ["#!/bin/bash"]
    for name in topological_order(components):
        lines.append(f'echo "Building {name}..."')
        lines.append(f'cd {by_name[name]["path"]} && make build')
    return "\n".join(lines)


def test_orchestrate_decodes_parses_and_sorts_unseen_manifests():
    manifest_path = "/home/user/manifest.b64"
    output_path = "/home/user/build_all.sh"
    orchestrate_path = "/home/user/orchestrate.py"

    with open(manifest_path, "rb") as f:
        original_manifest = f.read()
    original_output = None
    original_mode = None
    if os.path.isfile(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()
        original_mode = stat.S_IMODE(os.stat(output_path).st_mode)

    token = secrets.token_hex(6)
    cases = [
        [
            {"name": f"service-{token}", "language": "Python", "path": f"/home/user/src/{token}/service", "deps": [f"library-b-{token}", f"library-a-{token}"]},
            {"name": f"docs-{token}", "language": "Ruby", "path": f"/home/user/src/{token}/docs", "deps": []},
            {"name": f"library-b-{token}", "language": "Rust", "path": f"/home/user/src/{token}/lib-b", "deps": [f"core-{token}"]},
            {"name": f"core-{token}", "language": "Go", "path": f"/home/user/src/{token}/core", "deps": []},
            {"name": f"library-a-{token}", "language": "C", "path": f"/home/user/src/{token}/lib-a", "deps": [f"core-{token}"]},
        ],
        [
            {"name": f"package-{token}", "language": "Shell", "path": f"/home/user/work/{token}/package", "deps": [f"test-{token}", f"compile-{token}"]},
            {"name": f"test-{token}", "language": "Python", "path": f"/home/user/work/{token}/test", "deps": [f"compile-{token}"]},
            {"name": f"assets-{token}", "language": "JavaScript", "path": f"/home/user/work/{token}/assets", "deps": []},
            {"name": f"compile-{token}", "language": "Java", "path": f"/home/user/work/{token}/compile", "deps": [f"source-{token}"]},
            {"name": f"source-{token}", "language": "C++", "path": f"/home/user/work/{token}/source", "deps": []},
        ],
    ]

    try:
        for components in cases:
            with open(manifest_path, "wb") as f:
                f.write(encode_manifest(components))
            if os.path.lexists(output_path):
                os.remove(output_path)

            result = subprocess.run(
                ["python3", orchestrate_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, f"orchestrate.py failed: {result.stderr}"
            assert os.path.isfile(output_path), "orchestrate.py did not generate build_all.sh"
            assert os.stat(output_path).st_mode & stat.S_IXUSR, "Generated build_all.sh is not executable"

            with open(output_path, "r") as f:
                actual = f.read().strip()
            normalized_actual = "\n".join(line.strip() for line in actual.splitlines() if line.strip())
            normalized_expected = "\n".join(line.strip() for line in expected_script(components).splitlines() if line.strip())
            assert normalized_actual == normalized_expected, "orchestrate.py did not correctly decode, parse, and topologically sort the supplied manifest"
    finally:
        with open(manifest_path, "wb") as f:
            f.write(original_manifest)
        if original_output is None:
            if os.path.lexists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
            os.chmod(output_path, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
