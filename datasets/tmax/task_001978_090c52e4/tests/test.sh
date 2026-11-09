#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import re
import shutil
import subprocess
import tempfile
import uuid

PROTOS_DIR = "/home/user/protos"
API_PROTO = os.path.join(PROTOS_DIR, "api.proto")
MODELS_PROTO = os.path.join(PROTOS_DIR, "models.proto")
AUTH_PROTO = os.path.join(PROTOS_DIR, "auth.proto")
BASE_PROTO = os.path.join(PROTOS_DIR, "base.proto")
TOPOSORT_SCRIPT = "/home/user/toposort.py"
BUILD_ORDER_LOG = "/home/user/build_order.log"


def strip_comments(content):
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    return re.sub(r"//[^\n]*", "", content)


def message_body(content, name):
    match = re.search(r"\bmessage\s+" + re.escape(name) + r"\s*\{([^{}]*)\}", content, re.S)
    assert match, f"Missing or malformed message {name}."
    return match.group(1)


def parsed_fields(body):
    fields = re.findall(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+([A-Za-z_]\w*)\s*=\s*(\d+)\s*;", body)
    residue = re.sub(r"\b[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s+[A-Za-z_]\w*\s*=\s*\d+\s*;", "", body)
    assert not residue.strip(), f"Malformed or unexpected message contents: {residue!r}"
    return fields


def read_order():
    assert os.path.isfile(BUILD_ORDER_LOG), f"Log file {BUILD_ORDER_LOG} was not created."
    with open(BUILD_ORDER_LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_script():
    result = subprocess.run(
        ["python3", TOPOSORT_SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{TOPOSORT_SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def derive_order(directory):
    files = sorted(name for name in os.listdir(directory) if name.endswith(".proto"))
    file_set = set(files)
    dependencies = {}
    for name in files:
        with open(os.path.join(directory, name), "r") as f:
            content = strip_comments(f.read())
        imports = re.findall(r'\bimport\s+(?:public\s+|weak\s+)?"([^"]+)"\s*;', content)
        dependencies[name] = {dep for dep in imports if dep in file_set}

    reverse = {name: set() for name in files}
    indegree = {name: len(dependencies[name]) for name in files}
    for name, deps in dependencies.items():
        for dep in deps:
            reverse[dep].add(name)

    ready = [name for name in files if indegree[name] == 0]
    heapq.heapify(ready)
    order = []
    while ready:
        name = heapq.heappop(ready)
        order.append(name)
        for dependent in reverse[name]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)
    assert len(order) == len(files), "Verifier fixture unexpectedly contains a cycle."
    return order


def test_base_proto_created_correctly():
    assert os.path.isfile(BASE_PROTO), f"File {BASE_PROTO} was not created."
    with open(BASE_PROTO, "r") as f:
        content = f.read()
    assert 'syntax = "proto3";' in content, f"{BASE_PROTO} is missing syntax declaration."
    assert 'message ApiResponse' in content, f"{BASE_PROTO} is missing 'message ApiResponse'."


def test_api_proto_refactored():
    assert os.path.isfile(API_PROTO), f"File {API_PROTO} does not exist."
    with open(API_PROTO, "r") as f:
        content = f.read()
    assert 'message ApiResponse' not in content, f"'message ApiResponse' was not removed from {API_PROTO}."
    assert re.search(r'import\s+"base\.proto"\s*;', content), f"{API_PROTO} does not import 'base.proto'."


def test_models_proto_refactored():
    assert os.path.isfile(MODELS_PROTO), f"File {MODELS_PROTO} does not exist."
    with open(MODELS_PROTO, "r") as f:
        content = f.read()
    assert re.search(r'import\s+"api\.proto"\s*;', content) is None, f"{MODELS_PROTO} should no longer import 'api.proto'."
    assert re.search(r'import\s+"base\.proto"\s*;', content), f"{MODELS_PROTO} does not import 'base.proto'."


def test_toposort_script_exists():
    assert os.path.isfile(TOPOSORT_SCRIPT), f"Script {TOPOSORT_SCRIPT} does not exist."


def test_build_order_log():
    assert os.path.isfile(BUILD_ORDER_LOG), f"Log file {BUILD_ORDER_LOG} was not created."
    with open(BUILD_ORDER_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_order = [
        "base.proto",
        "models.proto",
        "auth.proto",
        "api.proto"
    ]

    assert lines == expected_order, f"Build order in {BUILD_ORDER_LOG} is incorrect. Expected {expected_order}, got {lines}."


def test_proto_refactor_is_structurally_valid_and_intact():
    paths = [API_PROTO, MODELS_PROTO, AUTH_PROTO, BASE_PROTO]
    contents = {}
    for path in paths:
        assert os.path.isfile(path), f"Missing proto file: {path}"
        with open(path, "r") as f:
            clean = strip_comments(f.read())
        assert re.match(r'^\s*syntax\s*=\s*"proto3"\s*;', clean), f"{path} lacks a valid proto3 declaration at the top."
        assert clean.count("{") == clean.count("}"), f"Unbalanced braces in {path}."
        contents[os.path.basename(path)] = clean

    assert parsed_fields(message_body(contents["base.proto"], "ApiResponse")) == [
        ("bool", "success", "1"),
        ("string", "message", "2"),
    ], "ApiResponse was not moved intact."
    assert parsed_fields(message_body(contents["api.proto"], "GetUserRequest")) == [
        ("string", "id", "1"),
    ]
    assert parsed_fields(message_body(contents["models.proto"], "User")) == [
        ("string", "id", "1"),
        ("string", "name", "2"),
        ("ApiResponse", "last_status", "3"),
    ]
    assert parsed_fields(message_body(contents["auth.proto"], "Token")) == [
        ("string", "token", "1"),
        ("User", "user", "2"),
    ]
    assert re.search(
        r"\bservice\s+ApiService\s*\{\s*rpc\s+GetUser\s*\(\s*GetUserRequest\s*\)\s*returns\s*\(\s*ApiResponse\s*\)\s*;\s*\}",
        contents["api.proto"], re.S
    ), "ApiService or its GetUser RPC was not preserved."

    local_files = set(contents)
    deps = {}
    for name, content in contents.items():
        imports = re.findall(r'\bimport\s+(?:public\s+|weak\s+)?"([^"]+)"\s*;', content)
        for imported in imports:
            assert imported.startswith("google/protobuf/") or imported in local_files, f"{name} imports missing local file {imported}."
        deps[name] = {item for item in imports if item in local_files}

    assert "base.proto" in deps["api.proto"]
    assert "base.proto" in deps["models.proto"]
    assert "api.proto" not in deps["models.proto"]
    assert "models.proto" in deps["auth.proto"]

    remaining = {name: set(values) for name, values in deps.items()}
    while remaining:
        ready = [name for name, values in remaining.items() if not values]
        assert ready, "The local proto import graph still contains a cycle."
        for name in ready:
            del remaining[name]
        for values in remaining.values():
            values.difference_update(ready)


def test_toposort_script_generates_current_build_order():
    if os.path.exists(BUILD_ORDER_LOG):
        os.remove(BUILD_ORDER_LOG)
    run_script()
    expected = derive_order(PROTOS_DIR)
    assert read_order() == expected, f"Script did not generate the derived order {expected}."


def test_toposort_script_handles_unseen_graph_and_alphabetical_ties():
    token = uuid.uuid4().hex
    names = [token[i:i + 6] + suffix + ".proto" for i, suffix in zip(range(0, 24, 4), "qazwsx")]
    backup_dir = tempfile.mkdtemp(prefix="saved_protos_", dir="/home/user")
    os.rmdir(backup_dir)
    prior_log_exists = os.path.exists(BUILD_ORDER_LOG)
    prior_log = b""
    if prior_log_exists:
        with open(BUILD_ORDER_LOG, "rb") as f:
            prior_log = f.read()

    os.rename(PROTOS_DIR, backup_dir)
    os.mkdir(PROTOS_DIR)
    try:
        dependency_sets = [
            [],
            [],
            [names[0]],
            [names[1]],
            [names[0], names[1]],
            [names[2], names[3]],
        ]
        for index, name in enumerate(names):
            imports = "".join(f'import "{dep}";\n' for dep in dependency_sets[index])
            if index == 4:
                imports += 'import "google/protobuf/timestamp.proto";\n'
            with open(os.path.join(PROTOS_DIR, name), "w") as f:
                f.write('syntax = "proto3";\n\n' + imports + f'\nmessage M{index} {{ string value = 1; }}\n')

        expected = derive_order(PROTOS_DIR)
        if os.path.exists(BUILD_ORDER_LOG):
            os.remove(BUILD_ORDER_LOG)
        run_script()
        actual = read_order()
        assert actual == expected, f"For an unseen dependency graph, expected {expected}, got {actual}."
    finally:
        shutil.rmtree(PROTOS_DIR, ignore_errors=True)
        os.rename(backup_dir, PROTOS_DIR)
        if prior_log_exists:
            with open(BUILD_ORDER_LOG, "wb") as f:
                f.write(prior_log)
        elif os.path.exists(BUILD_ORDER_LOG):
            os.remove(BUILD_ORDER_LOG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
