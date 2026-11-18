#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import secrets
import socket
import subprocess
import tempfile
import time

import pytest


def test_run_test_script_exists_and_executable():
    """Verify that /home/user/run_test.sh exists and is executable."""
    script_path = "/home/user/run_test.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_success_json_exists_and_correct():
    """Verify that /home/user/success.json exists and contains the correct response."""
    json_path = "/home/user/success.json"
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} does not contain valid JSON."

    assert "id" in data, f"Key 'id' missing in {json_path}."
    assert data["id"] == "task-999", f"Expected 'id' to be 'task-999', got '{data['id']}'."

    assert "status" in data, f"Key 'status' missing in {json_path}."
    assert data["status"] == "CREATED_V2", f"Expected 'status' to be 'CREATED_V2', got '{data['status']}'."


def test_script_performs_valid_live_grpc_request():
    """Run the submitted script against a live server and require a recorded valid RPC."""
    private_dir = tempfile.mkdtemp(prefix="grpc_verify_", dir="/root")
    os.chmod(private_dir, 0o700)
    proto_path = os.path.join(private_dir, "task.proto")
    marker_path = os.path.join(private_dir, "valid_rpc")
    ready_path = os.path.join(private_dir, "ready")
    token = secrets.token_hex(16)
    expected_id = "verify-" + token
    expected_status = "LIVE_" + token.upper()

    with open(proto_path, "w") as f:
        f.write('''syntax = "proto3";
package task;

enum Priority {
  UNKNOWN = 0;
  LOW = 1;
  MEDIUM = 2;
  HIGH = 3;
}

message CreateTaskRequest {
  string title = 1;
  Priority priority = 2;
  repeated string tags = 3;
}

message TaskResponse {
  string id = 1;
  string status = 2;
}

service TaskService {
  rpc CreateTask(CreateTaskRequest) returns (TaskResponse);
}
''')

    subprocess.run(
        ["python3", "-m", "grpc_tools.protoc", "-I" + private_dir,
         "--python_out=" + private_dir, "--grpc_python_out=" + private_dir,
         proto_path],
        check=True,
    )

    server_path = os.path.join(private_dir, "challenge_server.py")
    with open(server_path, "w") as f:
        f.write('''import sys
from concurrent import futures
import grpc
import task_pb2
import task_pb2_grpc
from grpc_reflection.v1alpha import reflection

marker, ready, response_id, response_status = sys.argv[1:5]

class Servicer(task_pb2_grpc.TaskServiceServicer):
    def CreateTask(self, request, context):
        if request.title != "Agent Test":
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "Incorrect title")
        if request.priority != task_pb2.HIGH:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "Priority must be HIGH")
        if "automation" not in request.tags:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "Missing automation tag")
        with open(marker, "w") as out:
            out.write("valid")
        return task_pb2.TaskResponse(id=response_id, status=response_status)

server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
task_pb2_grpc.add_TaskServiceServicer_to_server(Servicer(), server)
reflection.enable_server_reflection(
    (task_pb2.DESCRIPTOR.services_by_name["TaskService"].full_name,
     reflection.SERVICE_NAME), server)
if server.add_insecure_port("[::]:50051") == 0:
    raise RuntimeError("could not bind verification server")
server.start()
with open(ready, "w") as out:
    out.write("ready")
server.wait_for_termination()
''')

    # Replace the fixed service with a verifier-controlled instance whose response
    # cannot have been hardcoded before this test run.
    subprocess.run(["pkill", "-f", "/tmp/server.py"], check=False)
    time.sleep(0.5)
    server = subprocess.Popen(
        ["python3", server_path, marker_path, ready_path,
         expected_id, expected_status],
        cwd=private_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        deadline = time.time() + 10
        while time.time() < deadline and not os.path.exists(ready_path):
            if server.poll() is not None:
                stdout, stderr = server.communicate()
                pytest.fail(f"Verification server exited early: {stdout}\n{stderr}")
            time.sleep(0.1)
        assert os.path.exists(ready_path), "Verification server did not become ready."

        user = pwd.getpwnam("user")

        def demote():
            os.initgroups(user.pw_name, user.pw_gid)
            os.setgid(user.pw_gid)
            os.setuid(user.pw_uid)

        env = os.environ.copy()
        env["HOME"] = "/home/user"
        result = subprocess.run(
            ["/home/user/run_test.sh"],
            cwd="/home/user",
            env=env,
            preexec_fn=demote,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"run_test.sh failed with exit code {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(marker_path), (
            "The live server did not receive a valid CreateTask request from the script."
        )

        with open("/home/user/success.json", "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"success.json is not valid JSON after running the script: {exc}")

        assert data.get("id") == expected_id, "success.json was not produced by the live verification server."
        assert data.get("status") == expected_status, "success.json was not produced by the live verification server."
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
