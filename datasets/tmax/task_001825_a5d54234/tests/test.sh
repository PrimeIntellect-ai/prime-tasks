#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import sys
import tempfile

import pytest


def test_grpc_server_running_and_validating():
    workspace_dir = "/home/user/workspace"
    evil_dir = os.path.join(workspace_dir, "corpus", "evil")
    clean_dir = os.path.join(workspace_dir, "corpus", "clean")

    if not os.path.exists(evil_dir) or not os.path.exists(clean_dir):
        subprocess.run(
            ["make"], cwd=workspace_dir,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    assert os.path.exists(evil_dir), f"Evil corpus directory not found at {evil_dir}"
    assert os.path.exists(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    evil_files = glob.glob(os.path.join(evil_dir, "*.bin"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.bin"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."
    assert os.path.isfile(os.path.join(workspace_dir, "validator_server.py")), \
        "validator_server.py was not created."

    try:
        import grpc
        from grpc_tools import protoc
    except ImportError:
        pytest.fail("grpcio or grpcio-tools is not installed. The gRPC server cannot be tested.")

    proto_path = os.path.join(workspace_dir, "pipeline.proto")
    assert os.path.exists(proto_path), f"Protobuf definition not found at {proto_path}"

    with tempfile.TemporaryDirectory() as tmpdir:
        result = protoc.main((
            '',
            f'-I{workspace_dir}',
            f'--python_out={tmpdir}',
            f'--grpc_python_out={tmpdir}',
            proto_path,
        ))
        assert result == 0, "Failed to compile pipeline.proto"

        sys.path.insert(0, tmpdir)
        try:
            import pipeline_pb2
            import pipeline_pb2_grpc
        except ImportError as exc:
            pytest.fail(f"Failed to import compiled protobuf modules: {exc}")

        channel = grpc.insecure_channel('localhost:50051')
        try:
            grpc.channel_ready_future(channel).result(timeout=5)
        except grpc.FutureTimeoutError:
            pytest.fail("gRPC server is not listening on localhost:50051 or did not become ready in time.")

        stub = pipeline_pb2_grpc.AssetValidatorStub(channel)

        evil_bypassed = []
        for e_file in evil_files:
            with open(e_file, 'rb') as f:
                content = f.read()
            request = pipeline_pb2.AssetRequest(content=content)
            try:
                response = stub.ValidateAsset(request, timeout=3)
                if response.is_valid:
                    evil_bypassed.append(os.path.basename(e_file))
            except grpc.RpcError as exc:
                pytest.fail(f"RPC failed on evil file {os.path.basename(e_file)}: {exc}")

        clean_modified = []
        for c_file in clean_files:
            with open(c_file, 'rb') as f:
                content = f.read()
            request = pipeline_pb2.AssetRequest(content=content)
            try:
                response = stub.ValidateAsset(request, timeout=3)
                if not response.is_valid:
                    clean_modified.append(os.path.basename(c_file))
            except grpc.RpcError as exc:
                pytest.fail(f"RPC failed on clean file {os.path.basename(c_file)}: {exc}")

        errors = []
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
        if errors:
            pytest.fail(" | ".join(errors))

        # Exercise unseen payloads so a service hardcoded for the shipped corpus
        # cannot pass. Expected results are derived from each generated payload.
        trigger = bytes((15, 11))

        def safe_random(size):
            while True:
                value = os.urandom(size)
                if trigger not in value:
                    return value

        cases = [b'', bytes((15,)), bytes((11,)), bytes((15, 0, 11)), trigger]
        for _ in range(32):
            base = safe_random(random.randint(0, 512))
            cases.append(base)

            pos = random.randint(0, len(base))
            cases.append(base[:pos] + trigger + base[pos:])

        random.shuffle(cases)
        for index, content in enumerate(cases):
            expected_valid = trigger not in content
            try:
                response = stub.ValidateAsset(
                    pipeline_pb2.AssetRequest(content=content), timeout=3
                )
            except grpc.RpcError as exc:
                pytest.fail(f"RPC failed on generated case {index}: {exc}")
            assert response.is_valid == expected_valid, (
                f"Incorrect result for generated case {index}: "
                f"expected is_valid={expected_valid}, got {response.is_valid}"
            )

        channel.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
