#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import string
import subprocess
import tempfile
import uuid

ORACLE_PATH = "/app/oracle_query"
AGENT_SCRIPT = "/home/user/query.py"
VENDORED_ROOT = "/app/vendored/jmespath-1.0.1"
VENDORED_INIT = os.path.join(VENDORED_ROOT, "jmespath", "__init__.py")
N_TESTS = 100


def generate_random_json(depth=0):
    if depth > 3:
        return random.choice([
            random.randint(1, 100),
            ''.join(random.choices(string.ascii_letters, k=5))
        ])

    t = random.choice(['dict', 'list', 'int', 'str'])
    if t == 'dict':
        return {f"key_{i}": generate_random_json(depth + 1) for i in range(random.randint(1, 5))}
    elif t == 'list':
        return [generate_random_json(depth + 1) for _ in range(random.randint(1, 5))]
    elif t == 'int':
        return random.randint(1, 100)
    else:
        return ''.join(random.choices(string.ascii_letters, k=5))


def generate_random_query():
    queries = [
        "length(@)",
        "length(key_0)",
        "length(key_0 || `[]`)",
        "contains(@, `1`)",
        "contains(key_0 || `[]`, `10`)",
        "contains(@, `\"abc\"`)",
        "sort(@)",
        "sort(key_0 || `[]`)",
        "key_0",
        "key_0.key_1",
        "length(key_0.key_1 || `[]`)",
        "contains(key_1 || `[]`, `5`)",
    ]
    return random.choice(queries)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        json_path = os.path.join(tmpdir, "test.json")

        for i in range(N_TESTS):
            data = generate_random_json()
            query = generate_random_query()

            with open(json_path, "w") as f:
                json.dump(data, f)

            oracle_cmd = [ORACLE_PATH, json_path, query]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)

            agent_cmd = ["python3", AGENT_SCRIPT, json_path, query]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert oracle_res.returncode == agent_res.returncode, (
                f"Return code mismatch on iteration {i}.\n"
                f"Query: {query}\n"
                f"JSON: {json.dumps(data)}\n"
                f"Oracle returncode: {oracle_res.returncode}\n"
                f"Agent returncode: {agent_res.returncode}\n"
                f"Oracle stderr: {oracle_res.stderr}\n"
                f"Agent stderr: {agent_res.stderr}"
            )

            assert oracle_res.stdout == agent_res.stdout, (
                f"Output mismatch on iteration {i}.\n"
                f"Query: {query}\n"
                f"JSON: {json.dumps(data)}\n"
                f"Oracle output: {repr(oracle_res.stdout)}\n"
                f"Agent output: {repr(agent_res.stdout)}"
            )


def test_script_imports_vendored():
    with open(AGENT_SCRIPT, "r") as f:
        content = f.read()
    assert "sys.path.insert(0, '/app/vendored/jmespath-1.0.1')" in content or "sys.path.insert(0,'/app/vendored/jmespath-1.0.1')" in content or "sys.path.insert(0, \"/app/vendored/jmespath-1.0.1\")" in content, \
        "Agent script does not appear to prepend the vendored directory to sys.path."


def test_repaired_vendored_package_directly():
    assert os.path.isfile(VENDORED_INIT), "Vendored jmespath package is missing"
    code = r'''
import json
import os
import sys
sys.path.insert(0, "/app/vendored/jmespath-1.0.1")
import jmespath
root = os.path.realpath("/app/vendored/jmespath-1.0.1")
origin = os.path.realpath(jmespath.__file__)
assert os.path.commonpath([root, origin]) == root, origin
results = {
    "array_length": jmespath.search("length(@)", [1, 2, 3]),
    "string_length": jmespath.search("length(@)", "abcd"),
    "object_length": jmespath.search("length(@)", {"a": 1, "b": 2}),
    "contains_array_true": jmespath.search("contains(@, `2`)", [1, 2, 3]),
    "contains_array_false": jmespath.search("contains(@, `9`)", [1, 2, 3]),
    "contains_string_true": jmespath.search("contains(@, 'bc')", "abcd"),
    "contains_string_false": jmespath.search("contains(@, 'zz')", "abcd"),
    "sum": jmespath.search("sum(@)", [1, 2, 3, 4]),
    "avg": jmespath.search("avg(@)", [1, 2, 3, 4]),
    "min": jmespath.search("min(@)", [4, 1, 3]),
    "max": jmespath.search("max(@)", [4, 1, 3]),
    "projection": jmespath.search("items[?contains(name, 'a')].name", {"items": [{"name": "alpha"}, {"name": "echo"}, {"name": "beta"}]})
}
print(json.dumps(results, separators=(",", ":")))
'''
    expected = {
        "array_length": 3,
        "string_length": 4,
        "object_length": 2,
        "contains_array_true": True,
        "contains_array_false": False,
        "contains_string_true": True,
        "contains_string_false": False,
        "sum": 10,
        "avg": 2.5,
        "min": 1,
        "max": 4,
        "projection": ["alpha", "beta"]
    }
    result = subprocess.run(["python3", "-I", "-c", code], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout == json.dumps(expected, separators=(",", ":")) + "\n"


def test_entrypoint_really_imports_vendored_package():
    marker_path = os.path.join(tempfile.gettempdir(), "vendored-import-" + uuid.uuid4().hex)
    marker_token = uuid.uuid4().hex
    with open(VENDORED_INIT, "rb") as f:
        original = f.read()
    original_stat = os.stat(VENDORED_INIT)
    prefix = (
        "import os as _verifier_os\n"
        f"with open({marker_path!r}, 'w') as _verifier_marker:\n"
        f"    _verifier_marker.write({marker_token!r})\n"
    ).encode("utf-8")

    pycache = os.path.join(VENDORED_ROOT, "jmespath", "__pycache__")
    try:
        shutil.rmtree(pycache, ignore_errors=True)
        with open(VENDORED_INIT, "wb") as f:
            f.write(prefix)
            f.write(original)

        with tempfile.TemporaryDirectory() as tmpdir:
            json_path = os.path.join(tmpdir, "input.json")
            with open(json_path, "w") as f:
                json.dump({"values": [1, 2, 3]}, f)
            result = subprocess.run(
                ["python3", AGENT_SCRIPT, json_path, "length(values)"],
                capture_output=True,
                text=True,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )
            assert result.returncode == 0, result.stderr
            assert result.stdout == "3\n"

        assert os.path.isfile(marker_path), "query.py did not import the vendored jmespath package"
        with open(marker_path, "r") as f:
            assert f.read() == marker_token
    finally:
        with open(VENDORED_INIT, "wb") as f:
            f.write(original)
        os.chmod(VENDORED_INIT, original_stat.st_mode)
        os.utime(VENDORED_INIT, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
        shutil.rmtree(pycache, ignore_errors=True)
        try:
            os.unlink(marker_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
