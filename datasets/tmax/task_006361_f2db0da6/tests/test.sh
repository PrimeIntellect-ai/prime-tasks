#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import textwrap

PREFIX = b"Content-Type: application/json\r\n\r\n"
API = "/home/user/file_api"
TEST_SCRIPT = "/home/user/test_api.sh"


def run_api(binary, directory, extra_env=None):
    env = os.environ.copy()
    env["QUERY_STRING"] = "dir=" + directory
    if extra_env:
        env.update(extra_env)
    return subprocess.run([binary], env=env, capture_output=True, timeout=30)


def parse_response(result):
    assert result.returncode == 0, (
        f"API exited with {result.returncode}:\n"
        f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
    )
    assert result.stdout.startswith(PREFIX), (
        "Response does not strictly begin with the required CGI header: "
        f"{result.stdout[:100]!r}"
    )
    body = result.stdout[len(PREFIX):]
    try:
        return json.loads(body.decode("utf-8"))
    except Exception as exc:
        raise AssertionError(f"Response body is not valid JSON: {body!r}") from exc


def normalize_tree(value):
    assert isinstance(value, list), f"Directory value must be a JSON array, got {value!r}"
    result = {}
    for entry in value:
        assert isinstance(entry, dict) and len(entry) == 1, (
            f"Each tree entry must be a one-key object, got {entry!r}"
        )
        name, child = next(iter(entry.items()))
        assert name not in result, f"Duplicate tree entry {name!r}"
        if isinstance(child, list):
            result[name] = normalize_tree(child)
        else:
            assert isinstance(child, int) and not isinstance(child, bool), (
                f"File size for {name!r} must be an integer, got {child!r}"
            )
            result[name] = child
    return result


def test_file_api_executable():
    path = API
    assert os.path.isfile(path), f"File {path} does not exist"
    assert os.access(path, os.X_OK), f"File {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable"


def test_test_api_sh_executable():
    path = TEST_SCRIPT
    assert os.path.isfile(path), f"File {path} does not exist"
    assert os.access(path, os.X_OK), f"File {path} is not executable"


def test_required_compile_command_succeeds():
    res = subprocess.run(
        ["g++", "-O2", "-Wall", "/home/user/file_api.cpp", "-o", "/tmp/file_api_o2"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert res.returncode == 0, f"Required compilation failed:\n{res.stderr}"


def make_semantic_fixture(root):
    if os.path.exists(root):
        shutil.rmtree(root)
    os.makedirs(root)
    with open(os.path.join(root, "root_file.bin"), "wb") as f:
        f.write(bytes(range(37)))
    with open(os.path.join(root, "zero"), "wb"):
        pass
    os.makedirs(os.path.join(root, "empty_dir"))
    nested = os.path.join(root, "level_one", "level_two")
    os.makedirs(nested)
    with open(os.path.join(root, "level_one", "short.txt"), "wb") as f:
        f.write(b"hello world")
    long_name = "n" * 180
    with open(os.path.join(nested, long_name), "wb") as f:
        f.write(b"x" * 4097)
    return {
        "root_file.bin": 37,
        "zero": 0,
        "empty_dir": {},
        "level_one": {
            "short.txt": 11,
            "level_two": {long_name: 4097},
        },
    }


def test_file_api_response_and_recursive_tree_semantics():
    root = "/tmp/verify_semantic_tree"
    expected = make_semantic_fixture(root)
    for binary in (API, "/tmp/file_api_o2"):
        parsed = parse_response(run_api(binary, root))
        assert normalize_tree(parsed) == expected, (
            f"{binary} did not report the exact recursive names, types, and sizes"
        )


def test_file_api_asan_and_deep_dir():
    asan_bin = "/tmp/file_api_asan"
    compile_cmd = [
        "g++", "-fsanitize=address", "-g",
        "/home/user/file_api.cpp", "-o", asan_bin
    ]
    res = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert res.returncode == 0, f"Compilation with ASAN failed:\n{res.stderr}"

    deep_dir = "/tmp/verify_dir"
    if os.path.exists(deep_dir):
        shutil.rmtree(deep_dir)

    current_dir = deep_dir
    os.makedirs(current_dir)
    names = []
    for _ in range(6):
        name = "a" * 60
        names.append(name)
        current_dir = os.path.join(current_dir, name)
        os.makedirs(current_dir)
    leaf_name = "leaf_" + "z" * 170
    with open(os.path.join(current_dir, leaf_name), "wb") as f:
        f.write(b"q" * 1234)

    env = os.environ.copy()
    env["QUERY_STRING"] = f"dir={deep_dir}"
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"

    res = subprocess.run([asan_bin], env=env, capture_output=True, timeout=30)
    stderr = res.stderr.decode("utf-8", "replace")
    assert res.returncode == 0, (
        f"ASAN binary crashed or reported issues:\n{stderr}\n"
        f"{res.stdout.decode('utf-8', 'replace')}"
    )
    assert "AddressSanitizer" not in stderr, f"ASAN reported an error:\n{stderr}"
    actual = normalize_tree(parse_response(res))
    expected = {leaf_name: 1234}
    for name in reversed(names):
        expected = {name: expected}
    assert actual == expected, "Deep recursive tree output is incorrect"


def test_test_api_sh_success():
    res = subprocess.run(
        [TEST_SCRIPT], capture_output=True, text=True, cwd="/home/user", timeout=120
    )
    assert res.returncode == 0, (
        f"{TEST_SCRIPT} failed when it should succeed:\n"
        f"STDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
    )
    message = (res.stdout + res.stderr).lower()
    assert "success" in message or "passed" in message, (
        "test_api.sh did not print a success message"
    )


def replace_api(contents):
    with open(API, "wb") as f:
        f.write(contents)
    os.chmod(API, 0o755)


def run_script_with_bad_api(contents):
    original = open(API, "rb").read()
    original_mode = stat.S_IMODE(os.stat(API).st_mode)
    try:
        replace_api(contents)
        return subprocess.run(
            [TEST_SCRIPT], capture_output=True, text=True,
            cwd="/home/user", timeout=120
        )
    finally:
        with open(API, "wb") as f:
            f.write(original)
        os.chmod(API, original_mode)


def test_test_api_sh_failure():
    res = run_script_with_bad_api(b"#!/bin/bash\nexit 1\n")
    assert res.returncode != 0, (
        f"{TEST_SCRIPT} should have failed when file_api is broken, but exited with 0"
    )


def test_test_api_sh_checks_strict_header_and_json():
    mutants = [
        b"#!/bin/bash\nprintf 'junkContent-Type: application/json\\r\\n\\r\\n[]\\n'\nexit 0\n",
        b"#!/bin/bash\nprintf 'Content-Type: text/plain\\r\\n\\r\\n[]\\n'\nexit 0\n",
        b"#!/bin/bash\nprintf 'Content-Type: application/json\\r\\n\\r\\nnot-json\\n'\nexit 0\n",
    ]
    for mutant in mutants:
        res = run_script_with_bad_api(mutant)
        assert res.returncode != 0, (
            "test_api.sh accepted a response with an invalid header or JSON body:\n"
            f"stdout={res.stdout}\nstderr={res.stderr}"
        )


PROBE = textwrap.dedent(r'''#!/usr/bin/env python3
import hashlib
import json
import os
import sys

qs = os.environ.get("QUERY_STRING", "")
if not qs.startswith("dir="):
    sys.exit(1)
root = qs[4:]
records = []
for base, dirs, files in os.walk(root):
    dirs.sort()
    files.sort()
    for d in dirs:
        records.append(["d", os.path.relpath(os.path.join(base, d), root)])
    for name in files:
        path = os.path.join(base, name)
        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        records.append(["f", os.path.relpath(path, root), os.path.getsize(path), digest])
with open("/tmp/generation_probe.jsonl", "a") as log:
    log.write(json.dumps({"root": root, "records": records}) + "\n")

def tree(path):
    result = []
    for entry in sorted(os.scandir(path), key=lambda e: e.name):
        if entry.is_dir(follow_symlinks=False):
            result.append({entry.name: tree(entry.path)})
        elif entry.is_file(follow_symlinks=False):
            result.append({entry.name: entry.stat(follow_symlinks=False).st_size})
    return result

sys.stdout.buffer.write(b"Content-Type: application/json\r\n\r\n")
sys.stdout.write(json.dumps(tree(root)) + "\n")
''').encode()


def clean_generated_roots():
    for i in range(1, 11):
        path = f"/home/user/test_run_{i}"
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def run_generation_probe():
    original = open(API, "rb").read()
    original_mode = stat.S_IMODE(os.stat(API).st_mode)
    clean_generated_roots()
    if os.path.exists("/tmp/generation_probe.jsonl"):
        os.unlink("/tmp/generation_probe.jsonl")
    try:
        replace_api(PROBE)
        res = subprocess.run(
            [TEST_SCRIPT], capture_output=True, text=True,
            cwd="/home/user", timeout=120
        )
        assert res.returncode == 0, (
            "test_api.sh failed against a conforming instrumented API:\n"
            f"stdout={res.stdout}\nstderr={res.stderr}"
        )
        assert os.path.isfile("/tmp/generation_probe.jsonl"), (
            "test_api.sh never invoked /home/user/file_api"
        )
        with open("/tmp/generation_probe.jsonl") as f:
            events = [json.loads(line) for line in f if line.strip()]
    finally:
        with open(API, "wb") as f:
            f.write(original)
        os.chmod(API, original_mode)

    expected_roots = {f"/home/user/test_run_{i}" for i in range(1, 11)}
    seen = {event["root"] for event in events}
    assert expected_roots <= seen, (
        f"test_api.sh did not invoke the API for all ten required roots; saw {seen}"
    )

    snapshots = {}
    has_long = False
    for root in expected_roots:
        matching = [e["records"] for e in events if e["root"] == root]
        records = matching[-1]
        snapshots[root] = records
        files = [r for r in records if r[0] == "f"]
        dirs = [r for r in records if r[0] == "d"]
        assert files, f"{root} contained no files"
        assert dirs, f"{root} contained no subdirectories"
        for record in records:
            rel = record[1]
            depth = len(rel.split(os.sep))
            assert depth <= 4 if record[0] == "f" else depth <= 3, (
                f"Generated structure exceeds three directory levels: {rel}"
            )
            base = os.path.basename(rel)
            if len(base) >= 100 or len(os.path.join(root, rel)) >= 240:
                has_long = True
    assert has_long, "No exceptionally long filename or path was generated"
    return snapshots


def test_test_api_sh_generates_ten_random_structures():
    first = run_generation_probe()
    second = run_generation_probe()
    assert first != second, (
        "Two runs generated identical structures; test_api.sh does not appear to randomize its tests"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
