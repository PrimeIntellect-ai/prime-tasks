#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import secrets
import signal
import subprocess
import sys
import tempfile
import time

import cv2
import grpc
import numpy as np
import pytest

HOME = "/home/user"
SAMPLE_VIDEO = "/app/sample_video.mp4"


def test_01_adversarial_corpus():
    sys.path.insert(0, HOME)
    try:
        from validator import is_safe_expression
    except ImportError:
        pytest.fail("Could not import is_safe_expression from /home/user/validator.py")

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = sorted(f for f in os.listdir(clean_dir) if f.endswith(".txt"))
    evil_files = sorted(f for f in os.listdir(evil_dir) if f.endswith(".txt"))

    clean_failed = []
    for name in clean_files:
        with open(os.path.join(clean_dir, name), encoding="utf-8") as f:
            expr = f.read().strip()
        try:
            if not is_safe_expression(expr):
                clean_failed.append(name)
        except Exception:
            clean_failed.append(name)

    evil_failed = []
    for name in evil_files:
        with open(os.path.join(evil_dir, name), encoding="utf-8") as f:
            expr = f.read().strip()
        try:
            if is_safe_expression(expr):
                evil_failed.append(name)
        except Exception:
            pass

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))

    nonce = secrets.randbelow(10000) + 1
    extra_clean = [
        f"(r_mean - {nonce}.25) * 2 / 3 > g_mean and not (frame_index == {nonce} or b_mean != b_mean)",
        f"frame_index % {nonce + 2} == 0 or time_sec < {nonce}.5",
    ]
    extra_evil = [
        f"__import__('os').getenv('{nonce}')",
        f"r_mean ** {nonce}",
        f"allowed_{nonce} > 0",
        f"(r_mean).__class__",
        f"[frame_index][0] == {nonce}",
    ]
    for expr in extra_clean:
        assert is_safe_expression(expr) is True, f"Safe expression was rejected: {expr}"
    for expr in extra_evil:
        try:
            accepted = is_safe_expression(expr)
        except Exception:
            accepted = False
        assert accepted is False, f"Unsafe expression was accepted: {expr}"


def _kill_submitted_servers():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [x.decode(errors="ignore") for x in raw.split(b"\0") if x]
            cwd = os.readlink(f"/proc/{entry}/cwd")
        except (OSError, ProcessLookupError):
            continue
        if any(a == "/home/user/server.py" or (a == "server.py" and cwd == HOME) for a in args):
            try:
                os.kill(int(entry), signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.5)


def _wait_for_channel(channel, timeout=12):
    grpc.channel_ready_future(channel).result(timeout=timeout)


def _make_random_video(path):
    fps = 17.0
    width, height, count = 96, 64, 43
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    assert writer.isOpened(), "Could not create verifier video"
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(8), "big"))
    for _ in range(count):
        bgr = rng.integers(0, 256, size=3, dtype=np.uint8)
        frame = np.empty((height, width, 3), dtype=np.uint8)
        frame[:, :] = bgr
        writer.write(frame)
    writer.release()

    decoded = []
    cap = cv2.VideoCapture(path)
    assert cap.isOpened()
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        b, g, r = cv2.mean(frame)[:3]
        decoded.append((r, g, b))
    cap.release()
    assert len(decoded) == count
    return decoded


def test_02_artifacts_grpc_server_and_client():
    required = [
        "/home/user/video_query.proto",
        "/home/user/video_query_pb2.py",
        "/home/user/video_query_pb2_grpc.py",
        "/home/user/server.py",
        "/home/user/client.py",
    ]
    for path in required:
        assert os.path.isfile(path), f"Required artifact missing: {path}"
        assert os.path.getsize(path) > 0, f"Required artifact is empty: {path}"

    # The submitted proto source itself must compile, not merely coexist with stale modules.
    with tempfile.TemporaryDirectory() as out_dir:
        proc = subprocess.run(
            [sys.executable, "-m", "grpc_tools.protoc", "-I/home/user", f"--python_out={out_dir}",
             f"--grpc_python_out={out_dir}", "/home/user/video_query.proto"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
        )
        assert proc.returncode == 0, f"video_query.proto does not compile: {proc.stderr}"

    sys.path.insert(0, HOME)
    import video_query_pb2
    import video_query_pb2_grpc

    assert os.path.realpath(video_query_pb2.__file__) == "/home/user/video_query_pb2.py"
    assert os.path.realpath(video_query_pb2_grpc.__file__) == "/home/user/video_query_pb2_grpc.py"
    descriptor = video_query_pb2.DESCRIPTOR
    request = descriptor.message_types_by_name.get("QueryRequest")
    response = descriptor.message_types_by_name.get("QueryResponse")
    service = descriptor.services_by_name.get("VideoQuery")
    assert request is not None and [(f.name, f.type) for f in request.fields] == [
        ("video_path", f.TYPE_STRING), ("expression", f.TYPE_STRING)
    ]
    assert response is not None
    assert len(response.fields) == 1
    result_field = response.fields[0]
    assert result_field.name == "matching_frame_indices"
    assert result_field.type == result_field.TYPE_INT32
    assert result_field.label == result_field.LABEL_REPEATED
    assert service is not None and len(service.methods) == 1
    assert service.methods[0].name == "QueryFrames"

    _kill_submitted_servers()

    # First exercise the client against a recording server with an unpredictable reply.
    recorded = []
    sentinel = [secrets.randbelow(500000) + 500000, secrets.randbelow(500000) + 1000000]

    class RecordingServicer(video_query_pb2_grpc.VideoQueryServicer):
        def QueryFrames(self, request, context):
            recorded.append((request.video_path, request.expression))
            return video_query_pb2.QueryResponse(matching_frame_indices=sentinel)

    recording_server = grpc.server(concurrent.futures.ThreadPoolExecutor(max_workers=2))
    video_query_pb2_grpc.add_VideoQueryServicer_to_server(RecordingServicer(), recording_server)
    assert recording_server.add_insecure_port("localhost:50051") != 0
    recording_server.start()
    try:
        result_path = "/home/user/result.json"
        if os.path.exists(result_path):
            os.unlink(result_path)
        client_run = subprocess.run(
            [sys.executable, "/home/user/client.py"], cwd=HOME,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
        )
        assert client_run.returncode == 0, f"client.py failed: {client_run.stderr}"
        assert recorded == [(SAMPLE_VIDEO, "r_mean > g_mean + 20 and frame_index > 50")], \
            f"client.py made the wrong gRPC request: {recorded}"
        with open(result_path, encoding="utf-8") as f:
            assert json.load(f) == sentinel, "client.py did not save the server's response"
    finally:
        recording_server.stop(0).wait(5)

    # Launch the submitted server artifact and query a newly generated video.
    server_proc = subprocess.Popen(
        [sys.executable, "/home/user/server.py"], cwd=HOME,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        _wait_for_channel(channel)
        assert server_proc.poll() is None, "server.py exited before serving requests"
        stub = video_query_pb2_grpc.VideoQueryStub(channel)

        with tempfile.TemporaryDirectory() as td:
            random_video = os.path.join(td, "challenge.mp4")
            means = _make_random_video(random_video)
            scores = [r + g / 2.0 - b / 4.0 for r, g, b in means]
            ordered = sorted(scores)
            threshold = (ordered[len(ordered)//2 - 1] + ordered[len(ordered)//2]) / 2.0
            modulus = secrets.randbelow(5) + 3
            remainder = secrets.randbelow(modulus)
            expr = f"r_mean + g_mean / 2 - b_mean / 4 > {threshold!r} and frame_index % {modulus} != {remainder}"
            expected = [i for i, score in enumerate(scores) if score > threshold and i % modulus != remainder]
            assert expected and len(expected) < len(means)
            reply = stub.QueryFrames(
                video_query_pb2.QueryRequest(video_path=random_video, expression=expr), timeout=20
            )
            assert list(reply.matching_frame_indices) == expected, \
                f"Dynamic gRPC query returned {list(reply.matching_frame_indices)}, expected {expected}"

            lo = secrets.randbelow(10) + 3
            hi = lo + secrets.randbelow(15) + 5
            index_expr = f"frame_index > {lo} and frame_index < {hi}"
            index_expected = list(range(lo + 1, min(hi, len(means))))
            reply = stub.QueryFrames(
                video_query_pb2.QueryRequest(video_path=random_video, expression=index_expr), timeout=20
            )
            assert list(reply.matching_frame_indices) == index_expected

        dynamic_bad = f"__import__('os').system('echo {secrets.token_hex(8)}')"
        with pytest.raises(grpc.RpcError) as caught:
            stub.QueryFrames(
                video_query_pb2.QueryRequest(video_path=SAMPLE_VIDEO, expression=dynamic_bad), timeout=10
            )
        assert caught.value.code() == grpc.StatusCode.INVALID_ARGUMENT

        # Regenerate the required final result by actually executing the submitted client
        # against the submitted server.
        if os.path.exists("/home/user/result.json"):
            os.unlink("/home/user/result.json")
        client_run = subprocess.run(
            [sys.executable, "/home/user/client.py"], cwd=HOME,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
        assert client_run.returncode == 0, f"client.py failed against server.py: {client_run.stderr}"
    finally:
        channel.close()
        if server_proc.poll() is None:
            server_proc.terminate()
            try:
                server_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server_proc.kill()
                server_proc.wait(timeout=5)


def test_03_result_json():
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"File {result_path} not found"

    with open(result_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{result_path} is not valid JSON")

    assert isinstance(data, list), "Result must be a JSON array"
    assert all(isinstance(x, int) for x in data), "Result array must contain only integers"

    cap = cv2.VideoCapture(SAMPLE_VIDEO)
    assert cap.isOpened(), f"Could not open {SAMPLE_VIDEO}"
    frame_index = 0
    expected_indices = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        b_mean, g_mean, r_mean = cv2.mean(frame)[:3]
        if r_mean > g_mean + 20 and frame_index > 50:
            expected_indices.append(frame_index)
        frame_index += 1
    cap.release()

    assert data == expected_indices, f"Result indices do not match ground truth. Expected {expected_indices}, got {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
