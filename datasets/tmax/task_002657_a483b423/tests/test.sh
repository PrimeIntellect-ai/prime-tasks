#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import sys
import tempfile


def run_script(directory, env=None):
    script_path = "/home/user/manifest_filter.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    result = subprocess.run(
        [sys.executable, script_path, directory],
        capture_output=True,
        text=True,
        env=env,
    )
    return result.stdout.strip().split('\n'), result.stderr, result.returncode


def test_clean_corpus():
    clean_dir = "/home/user/data/clean_manifests/"
    files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(files) > 0, "No clean manifests found in the setup."

    stdout_lines, stderr, returncode = run_script(clean_dir)

    results = {}
    for line in stdout_lines:
        if ":" in line:
            filename, status = line.split(":", 1)
            results[filename.strip()] = status.strip()

    failed_files = []
    for f in files:
        basename = os.path.basename(f)
        if results.get(basename) != "ACCEPT":
            failed_files.append(basename)

    assert not failed_files, f"{len(failed_files)} of {len(files)} clean modified (rejected or missing): {failed_files}. Script stderr: {stderr}"


def test_evil_corpus():
    evil_dir = "/home/user/data/evil_manifests/"
    files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(files) > 0, "No evil manifests found in the setup."

    stdout_lines, stderr, returncode = run_script(evil_dir)

    results = {}
    for line in stdout_lines:
        if ":" in line:
            filename, status = line.split(":", 1)
            results[filename.strip()] = status.strip()

    failed_files = []
    for f in files:
        basename = os.path.basename(f)
        if results.get(basename) != "REJECT":
            failed_files.append(basename)

    assert not failed_files, f"{len(failed_files)} of {len(files)} evil bypassed (accepted or missing): {failed_files}. Script stderr: {stderr}"


def test_vendored_package_fixed():
    """Ensure the vendored package can be imported without errors."""
    lib_path = "/app/graph-backup-lib"
    assert os.path.isdir(lib_path), f"Directory {lib_path} is missing."

    result = subprocess.run(
        [sys.executable, "-c", "import sys; sys.path.insert(0, '/app/graph-backup-lib'); import graph_backup_lib"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to import graph_backup_lib. The package is still broken.\nStderr: {result.stderr}"


def test_vendored_parser_runs():
    manifest = {
        "nodes": [{"id": "probe", "timestamp": "1672531200", "checksum": "probe"}],
        "edges": [],
    }
    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "probe.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)
        code = (
            "import sys; "
            "sys.path.insert(0, '/app/graph-backup-lib'); "
            "from graph_backup_lib.parser import parse_graph; "
            "data=parse_graph(sys.argv[1]); "
            "assert data['nodes'][0]['id']=='probe' and data['edges']==[]"
        )
        result = subprocess.run([sys.executable, "-c", code, path], capture_output=True, text=True)
        assert result.returncode == 0, f"graph_backup_lib.parser.parse_graph could not run. Stderr: {result.stderr}"


def test_generated_mixed_corpus_and_library_usage():
    def node(node_id, timestamp=None, checksum_marker=True):
        value = {
            "id": node_id,
            "timestamp": timestamp if timestamp is not None else str(random.randint(1000000000, 1999999999)),
        }
        if checksum_marker:
            value["checksum"] = secrets.token_hex(12)
        return value

    def ids(count):
        return [secrets.token_hex(8) for _ in range(count)]

    cases = []

    a, b, c, d = ids(4)
    cases.append(({
        "nodes": [node(a), node(b), node(c), node(d)],
        "edges": [{"from": a, "to": b}, {"from": b, "to": c}, {"from": c, "to": d}],
    }, "ACCEPT"))

    a, b, c, d = ids(4)
    cases.append(({
        "nodes": [node(a), node(b), node(c), node(d)],
        "edges": [{"from": a, "to": b}, {"from": a, "to": c}, {"from": b, "to": d}, {"from": c, "to": d}],
    }, "ACCEPT"))

    a = ids(1)[0]
    cases.append(({"nodes": [node(a)], "edges": []}, "ACCEPT"))

    a, b = ids(2)
    cases.append(({
        "nodes": [node(a), node(b)],
        "edges": [],
    }, "REJECT"))

    root, leaf, x, y = ids(4)
    cases.append(({
        "nodes": [node(root), node(leaf), node(x), node(y)],
        "edges": [{"from": root, "to": leaf}, {"from": x, "to": y}, {"from": y, "to": x}],
    }, "REJECT"))

    root, leaf, loop = ids(3)
    cases.append(({
        "nodes": [node(root), node(leaf), node(loop)],
        "edges": [{"from": root, "to": leaf}, {"from": loop, "to": loop}],
    }, "REJECT"))

    a, b = ids(2)
    cases.append(({
        "nodes": [node(a), node(b, checksum_marker=False)],
        "edges": [{"from": a, "to": b}],
    }, "REJECT"))

    a, b = ids(2)
    cases.append(({
        "nodes": [node(a), node(b, timestamp="123456789")],
        "edges": [{"from": a, "to": b}],
    }, "REJECT"))

    a, b = ids(2)
    cases.append(({
        "nodes": [node(a), node(b, timestamp=1672531201)],
        "edges": [{"from": a, "to": b}],
    }, "REJECT"))

    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="manifest_probe_") as directory, tempfile.TemporaryDirectory(prefix="site_probe_") as site_dir:
        expected = {}
        for manifest, status in cases:
            filename = secrets.token_hex(10) + ".json"
            with open(os.path.join(directory, filename), "w", encoding="utf-8") as handle:
                json.dump(manifest, handle)
            expected[filename] = status

        malformed_name = secrets.token_hex(10) + ".json"
        with open(os.path.join(directory, malformed_name), "w", encoding="utf-8") as handle:
            handle.write('{"nodes": [')
        expected[malformed_name] = "REJECT"

        marker = os.path.join(site_dir, "parser-called")
        sitecustomize = os.path.join(site_dir, "sitecustomize.py")
        with open(sitecustomize, "w", encoding="utf-8") as handle:
            handle.write(
                "import os, sys\n"
                "_marker = os.environ.get('GRAPH_BACKUP_TRACE_MARKER')\n"
                "def _trace(frame, event, arg):\n"
                "    if event == 'call' and frame.f_code.co_name == 'parse_graph':\n"
                "        module = frame.f_globals.get('__name__', '')\n"
                "        if module == 'graph_backup_lib' or module.startswith('graph_backup_lib.'):\n"
                "            with open(_marker, 'a', encoding='utf-8') as f:\n"
                "                f.write('called\\n')\n"
                "    return _trace\n"
                "if _marker:\n"
                "    sys.setprofile(_trace)\n"
            )

        env = os.environ.copy()
        env["GRAPH_BACKUP_TRACE_MARKER"] = marker
        old_pythonpath = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = site_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")

        stdout_lines, stderr, returncode = run_script(directory, env=env)
        assert returncode == 0, f"Classifier failed on generated corpus with code {returncode}. Stderr: {stderr}"

        expected_lines = {f"{filename}: {status}" for filename, status in expected.items()}
        actual_lines = stdout_lines if stdout_lines != [""] else []
        assert len(actual_lines) == len(expected_lines), (
            f"Expected exactly one output line per JSON file. Expected {len(expected_lines)}, "
            f"got {len(actual_lines)}: {actual_lines}. Stderr: {stderr}"
        )
        assert set(actual_lines) == expected_lines, (
            f"Incorrect or malformed classifications. Expected {sorted(expected_lines)}, "
            f"got {sorted(actual_lines)}. Stderr: {stderr}"
        )
        assert os.path.exists(marker) and os.path.getsize(marker) > 0, (
            "manifest_filter.py did not call graph_backup_lib.parser.parse_graph while classifying manifests"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
