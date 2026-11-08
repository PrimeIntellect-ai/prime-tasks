#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import math
import os
import secrets
import subprocess
import time

PR_DIR = "/home/user/waf_pr"
SERVER_PATH = os.path.join(PR_DIR, "waf_server")


def test_waf_server_compiled():
    """Check if the waf_server binary has been compiled successfully."""
    assert os.path.isfile(SERVER_PATH), f"The binary {SERVER_PATH} does not exist. Did you fix the Makefile and run make?"
    assert os.access(SERVER_PATH, os.X_OK), f"The file {SERVER_PATH} is not executable."


def test_results_log_correct():
    """Verify that results.log contains the correct output from the integration tests."""
    log_path = os.path.join(PR_DIR, "results.log")
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist. Did you run the integration script?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Test 1: BLOCK",
        'action": "BLOCK"',
        "Test 2: ALLOW",
        'action": "ALLOW"',
        "Test 3: CHALLENGE",
        'action": "CHALLENGE"'
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in results.log, but found {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in results.log is incorrect. Expected '{expected}', got '{actual}'."


def test_clean_build_and_live_grpc_behavior():
    # Require the submitted Makefile to recreate the generated gRPC sources and
    # a real native executable rather than accepting a pre-created executable.
    subprocess.run(["make", "clean"], cwd=PR_DIR, check=True, timeout=30)
    for path in [SERVER_PATH] + glob.glob(os.path.join(PR_DIR, "*.o")) + glob.glob(os.path.join(PR_DIR, "waf*.pb.cc")) + glob.glob(os.path.join(PR_DIR, "waf*.pb.h")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make"], cwd=PR_DIR, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=120
    )
    assert build.returncode == 0, "make failed:\n" + build.stdout
    assert os.path.isfile(SERVER_PATH) and os.access(SERVER_PATH, os.X_OK)
    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "waf_server is not a compiled ELF executable"
    for name in ("waf.pb.h", "waf.pb.cc", "waf.grpc.pb.h", "waf.grpc.pb.cc"):
        assert os.path.isfile(os.path.join(PR_DIR, name)), f"make did not generate {name}"

    verifier_proto = "/tmp/waf_verify.proto"
    with open(verifier_proto, "w") as f:
        f.write('''syntax = "proto3";
package waf;
service WafService { rpc EvaluateRisk (RiskRequest) returns (RiskResponse) {} }
enum Action { UNKNOWN = 0; ALLOW = 1; CHALLENGE = 2; BLOCK = 3; }
message RiskRequest {
  int32 total_requests = 1;
  int32 time_window_seconds = 2;
  int32 failed_logins = 3;
  float ip_trust_score = 4;
}
message RiskResponse { Action action = 1; float risk_score = 2; }
''')

    subprocess.run(["pkill", "-x", "waf_server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    proc = subprocess.Popen(
        [SERVER_PATH], cwd=PR_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, start_new_session=True
    )

    def invoke(case):
        cmd = [
            "grpcurl", "-plaintext", "-import-path", "/tmp",
            "-proto", "waf_verify.proto", "-d", json.dumps(case),
            "localhost:50051", "waf.WafService/EvaluateRisk"
        ]
        result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f"gRPC request failed: {result.stderr}"
        return json.loads(result.stdout)

    try:
        probe = {"total_requests": 1, "time_window_seconds": 1, "failed_logins": 0, "ip_trust_score": 0.9}
        last_error = None
        for _ in range(30):
            assert proc.poll() is None, "waf_server exited before accepting requests"
            try:
                invoke(probe)
                last_error = None
                break
            except (AssertionError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
                last_error = exc
                time.sleep(0.2)
        assert last_error is None, f"waf_server did not become ready: {last_error}"

        cases = [
            (100, 2, 0, 0.9),
            (10, 3, 0, 0.9),
            (10, 3, 0, 0.1),
            (20, 1, 2, 0.1),       # exactly 50: CHALLENGE
            (20, 1, 2, 0.2),       # exactly 50: ALLOW
            (101, 3, 0, 0.9),      # just over 50: BLOCK
            (33, 10, 0, 0.9),      # catches integer division in the score
            (0, 7, 0, 0.1),
        ]
        rng = secrets.SystemRandom()
        for _ in range(20):
            cases.append((rng.randrange(0, 500), rng.randrange(1, 31), rng.randrange(0, 7), rng.choice([0.05, 0.1, 0.19, 0.2, 0.35, 0.9])))

        for total, window, failed, trust in cases:
            request_rate = ctypes.c_float(total / window).value
            expected_score = ctypes.c_float(request_rate * 1.5 + failed * 10.0).value
            if expected_score > 50.0:
                expected_action = "BLOCK"
            elif trust < 0.2:
                expected_action = "CHALLENGE"
            else:
                expected_action = "ALLOW"

            response = invoke({
                "total_requests": total,
                "time_window_seconds": window,
                "failed_logins": failed,
                "ip_trust_score": trust,
            })
            actual_action = response.get("action", "UNKNOWN")
            actual_score = float(response.get("riskScore", 0.0))
            assert actual_action == expected_action, (
                f"wrong action for total={total}, window={window}, failed={failed}, trust={trust}: "
                f"expected {expected_action}, got {actual_action}"
            )
            assert math.isclose(actual_score, expected_score, rel_tol=1e-5, abs_tol=1e-3), (
                f"wrong risk score for total={total}, window={window}, failed={failed}: "
                f"expected {expected_score}, got {actual_score}"
            )
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
