#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import secrets
import pytest


def test_files_exist():
    assert os.path.isfile("/home/user/app/video.proto"), "video.proto is missing"
    assert os.path.isfile("/home/user/app/server.py"), "server.py is missing"
    assert os.path.isfile("/home/user/app/ci_setup.sh"), "ci_setup.sh is missing"
    assert os.access("/home/user/app/ci_setup.sh", os.X_OK), "ci_setup.sh is not executable"
    assert os.path.isfile("/home/user/app/server.pid"), "server.pid is missing, server might not be running"


def test_grpc_service():
    sys.path.insert(0, '/home/user/app')
    try:
        import video_pb2
        import video_pb2_grpc
        import grpc
        import cv2
        import numpy as np
    except ImportError as e:
        pytest.fail(f"Failed to import required modules. Did ci_setup.sh install them and compile the proto? Error: {e}")

    video_path = '/app/sample.mp4'
    assert os.path.isfile(video_path), "Sample video is missing from /app/sample.mp4"

    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), "Failed to open /app/sample.mp4"

    frame_variances = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        frame_variances.append(float(np.var(gray)))
    cap.release()

    assert len(frame_variances) >= 21, "Could not read frames 10 to 20 from video"

    # Retain the original request, then add unpredictable valid ranges so the
    # implementation must honor start_frame and end_frame rather than returning
    # a result hard-coded for frames 10 through 20.
    rng = secrets.SystemRandom()
    requests = [(10, 20), (0, 0), (len(frame_variances) - 1, len(frame_variances) - 1)]
    while len(requests) < 8:
        start = rng.randrange(len(frame_variances))
        end = rng.randrange(start, len(frame_variances))
        if (start, end) not in requests:
            requests.append((start, end))
    rng.shuffle(requests)

    channel = grpc.insecure_channel('localhost:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
        stub = video_pb2_grpc.VideoProcessorStub(channel)
        for start, end in requests:
            expected_variance = float(np.mean(frame_variances[start:end + 1]))
            request = video_pb2.FrameRangeRequest(start_frame=start, end_frame=end)
            response = stub.AnalyzeFrameRange(request, timeout=10)
            actual_variance = response.average_variance
            assert abs(actual_variance - expected_variance) < 0.1, \
                (f"For inclusive range [{start}, {end}], expected average variance "
                 f"~{expected_variance:.3f}, but got {actual_variance:.3f}")
    except grpc.RpcError as e:
        pytest.fail(f"gRPC call failed: {e}")
    except grpc.FutureTimeoutError:
        pytest.fail("gRPC server did not become ready on localhost:50051")
    finally:
        channel.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
