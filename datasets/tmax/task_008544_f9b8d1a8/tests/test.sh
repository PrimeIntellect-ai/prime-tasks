#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

WORKSPACE_DIR = "/home/user/workspace"
ROUTES_FILE = os.path.join(WORKSPACE_DIR, "routes.txt")
PROTO_FILE = os.path.join(WORKSPACE_DIR, "api.proto")
SOURCE_FILE = os.path.join(WORKSPACE_DIR, "generate_proto.cpp")
BINARY_FILE = os.path.join(WORKSPACE_DIR, "generate_proto")

EXPECTED_PATCHED_ROUTES = [
    "GET /health HealthCheck",
    "GET /users/<int:user_id> GetUser",
    "POST /users/<int:user_id>/update UpdateUser",
    "PUT /users/<int:user_id>/profile/<str:profile_type> UpdateProfile",
]


def read_nonempty_routes():
    with open(ROUTES_FILE, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def expected_proto(route_lines):
    routes = []
    parameter_re = re.compile(r"<(?P<type>int|str):(?P<name>[A-Za-z_][A-Za-z0-9_]*)>")

    for line in route_lines:
        parts = line.split()
        assert len(parts) == 3, f"Invalid test route: {line!r}"
        method, url, rpc = parts
        assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", rpc)

        parameters = []
        for match in parameter_re.finditer(url):
            proto_type = "int32" if match.group("type") == "int" else "string"
            parameters.append((proto_type, match.group("name")))
        routes.append((method, url, rpc, parameters))

    output = [
        'syntax = "proto3";',
        "package api;",
        "",
        "service ApiService {",
    ]
    for _, _, rpc, _ in routes:
        output.append(f"  rpc {rpc}({rpc}Request) returns ({rpc}Response);")
    output.append("}")

    for _, _, rpc, parameters in routes:
        output.extend(["", f"message {rpc}Request {{"])
        for number, (proto_type, name) in enumerate(parameters, 1):
            output.append(f"  {proto_type} {name} = {number};")
        output.extend(["}", "", f"message {rpc}Response {{", "}"])

    return "\n".join(output) + "\n"


def run_generator():
    result = subprocess.run(
        [BINARY_FILE],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"generate_proto exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PROTO_FILE), "generate_proto did not create api.proto"


def test_routes_file_is_patched():
    """Ensure the patch was successfully applied to routes.txt."""
    assert os.path.isfile(ROUTES_FILE), f"File {ROUTES_FILE} does not exist"
    with open(ROUTES_FILE, "r") as f:
        content = f.read()

    assert "PUT /users/<int:user_id>/profile/<str:profile_type> UpdateProfile" in content, "Patch was not applied: new route missing."
    assert "DELETE /legacy/<str:resource_id> DeleteLegacy" not in content, "Patch was not applied: old route still present."
    assert read_nonempty_routes() == EXPECTED_PATCHED_ROUTES, "routes.txt does not exactly match the patched route set and order."


def test_api_proto_exists_and_content():
    """Retain the original checks on the submitted api.proto."""
    assert os.path.isfile(PROTO_FILE), f"File {PROTO_FILE} does not exist. C++ program may not have run or failed."

    with open(PROTO_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
        content = " ".join(lines)

    assert 'syntax = "proto3";' in lines, "Missing or incorrect proto3 syntax declaration."
    assert 'package api;' in lines, "Missing or incorrect package declaration."
    assert 'service ApiService {' in content or 'service ApiService{' in content, "Missing ApiService definition."

    expected_rpcs = [
        "rpc HealthCheck(HealthCheckRequest) returns (HealthCheckResponse);",
        "rpc GetUser(GetUserRequest) returns (GetUserResponse);",
        "rpc UpdateUser(UpdateUserRequest) returns (UpdateUserResponse);",
        "rpc UpdateProfile(UpdateProfileRequest) returns (UpdateProfileResponse);"
    ]
    for rpc in expected_rpcs:
        compact_rpc = rpc.replace(" ", "")
        compact_content = content.replace(" ", "")
        assert compact_rpc in compact_content, f"Missing or incorrectly formatted RPC: {rpc}"

    compact_content = content.replace(" ", "")
    assert "messageUpdateProfileRequest{int32user_id=1;stringprofile_type=2;}" in compact_content or \
           ("int32user_id=1;" in compact_content and "stringprofile_type=2;" in compact_content), \
           "Missing or incorrect fields in UpdateProfileRequest."
    assert "messageHealthCheckResponse{}" in compact_content, "HealthCheckResponse should be empty."
    assert "messageUpdateProfileResponse{}" in compact_content, "UpdateProfileResponse should be empty."


def test_generator_compiles_runs_and_derives_complete_output_from_routes():
    assert os.path.exists(SOURCE_FILE), "generate_proto.cpp does not exist"
    source_stat = os.stat(SOURCE_FILE)
    assert stat.S_ISREG(source_stat.st_mode), "generate_proto.cpp is not a regular file"
    assert source_stat.st_size > 0, "generate_proto.cpp is empty"
    assert not os.path.isdir(BINARY_FILE), "generate_proto output path is a directory"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "generate_proto.cpp", "-o", "generate_proto"],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"generate_proto.cpp failed to compile.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY_FILE) and os.access(BINARY_FILE, os.X_OK), "Compiled generator is not executable"

    run_generator()
    with open(PROTO_FILE, "r", encoding="utf-8") as f:
        generated = f.read()
    assert generated == expected_proto(EXPECTED_PATCHED_ROUTES), (
        "api.proto does not have the required complete structure, ordering, fields, empty responses, or two-space indentation"
    )

    with open(ROUTES_FILE, "rb") as f:
        original_routes = f.read()
    original_proto = generated.encode("utf-8")

    token = secrets.token_hex(6)
    dynamic_routes = [
        f"PATCH /plain/{token} Probe{token}",
        f"POST /items/<str:item_{token}>/versions/<int:version_{token}> Store{token}",
        f"GET /groups/<int:group_{token}>/members/<str:member_{token}>/rank/<int:rank_{token}> Lookup{token}",
    ]

    try:
        with open(ROUTES_FILE, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(dynamic_routes) + "\n")
        if os.path.exists(PROTO_FILE):
            os.remove(PROTO_FILE)
        run_generator()
        with open(PROTO_FILE, "r", encoding="utf-8") as f:
            dynamic_proto = f.read()
        assert dynamic_proto == expected_proto(dynamic_routes), (
            "The compiled generator did not derive the exact RPCs, request fields, numbering, responses, ordering, and formatting from changed routes.txt input"
        )
    finally:
        with open(ROUTES_FILE, "wb") as f:
            f.write(original_routes)
        with open(PROTO_FILE, "wb") as f:
            f.write(original_proto)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
