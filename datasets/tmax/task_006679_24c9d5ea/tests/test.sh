#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import time
import socket
import pytest

def test_post_receive_hook_exists_and_executable():
    hook_path = "/home/user/repo.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Post-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"Post-receive hook at {hook_path} is not executable"

def test_router_script_exists():
    router_path = "/home/user/router.py"
    assert os.path.isfile(router_path), f"Router script not found at {router_path}"

def test_system_integration():
    # Ensure active_port.txt is removed to test the 503 fallback
    active_port_file = "/home/user/active_port.txt"
    if os.path.exists(active_port_file):
        os.remove(active_port_file)

    # Start the router in the background
    router_proc = subprocess.Popen(["python3", "/home/user/router.py"])
    time.sleep(2)  # Give the router time to start listening

    try:
        # 1. Test 503 response (no active_port.txt exists initially, or no backend)
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        try:
            s.connect(("127.0.0.1", 8080))
            s.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
            resp = s.recv(4096).decode('utf-8', errors='ignore')
        except Exception as e:
            pytest.fail(f"Failed to connect to router or receive response: {e}")
        finally:
            s.close()

        assert "503" in resp, f"Expected HTTP 503 response, got: {resp}"
        assert "Backend offline" in resp, f"Expected 'Backend offline' in body, got: {resp}"

        # 2. Make a commit and push
        workspace = "/home/user/workspace"
        index_path = os.path.join(workspace, "index.html")
        with open(index_path, "w") as f:
            f.write("test_v2")

        subprocess.run(["git", "add", "index.html"], cwd=workspace, check=True)
        subprocess.run(["git", "commit", "-m", "v2"], cwd=workspace, check=True)

        push_res = subprocess.run(["git", "push", "origin", "master"], cwd=workspace, capture_output=True, text=True)
        assert push_res.returncode == 0, f"Git push failed: {push_res.stderr}"

        time.sleep(2)  # Wait for hook to spin up server

        # 3. Test proxy forwarding
        s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s2.settimeout(2)
        try:
            s2.connect(("127.0.0.1", 8080))
            s2.sendall(b"GET /index.html HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
            resp2 = b""
            while True:
                chunk = s2.recv(4096)
                if not chunk:
                    break
                resp2 += chunk
            resp2 = resp2.decode('utf-8', errors='ignore')
        except Exception as e:
            pytest.fail(f"Failed to connect to router for proxy test: {e}")
        finally:
            s2.close()

        assert "200" in resp2, f"Expected HTTP 200 OK, got: {resp2}"
        assert "test_v2" in resp2, f"Expected 'test_v2' in response body, got: {resp2}"

        # 4. Test storage quota
        # Create dummy file > 500,000 bytes
        dummy_file = "/home/user/deployments/dummy.bin"
        with open(dummy_file, "wb") as f:
            f.write(b"\0" * 600000)

        with open(index_path, "w") as f:
            f.write("test_v3")

        subprocess.run(["git", "add", "index.html"], cwd=workspace, check=True)
        subprocess.run(["git", "commit", "-m", "v3"], cwd=workspace, check=True)

        new_rev = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=workspace,
            capture_output=True, text=True, check=True
        ).stdout.strip()
        old_rev = subprocess.run(
            ["git", "rev-parse", "HEAD^"], cwd=workspace,
            capture_output=True, text=True, check=True
        ).stdout.strip()

        push_res2 = subprocess.run(["git", "push", "origin", "master"], cwd=workspace, capture_output=True, text=True)

        # A post-receive hook runs after refs are updated, so its exit status cannot
        # reject the push. The push must succeed while relaying the hook's error.
        assert push_res2.returncode == 0, f"Post-receive hook unexpectedly caused push failure: {push_res2.stderr}"
        assert "Storage quota exceeded" in push_res2.stderr, f"Expected 'Storage quota exceeded' in stderr, got: {push_res2.stderr}"
        assert not os.path.exists(os.path.join("/home/user/deployments", new_rev)), "Over-quota revision should not be deployed"

        # Execute the hook directly to verify its required exit status and exact
        # stderr independently of Git's post-receive exit-status semantics.
        hook_res = subprocess.run(
            ["/home/user/repo.git/hooks/post-receive"],
            input=f"{old_rev} {new_rev} refs/heads/master\n",
            capture_output=True,
            text=True,
        )
        assert hook_res.returncode == 1, f"Quota-exceeded hook should exit 1, got {hook_res.returncode}"
        assert hook_res.stderr == "Storage quota exceeded\n", f"Unexpected quota stderr: {hook_res.stderr!r}"

    finally:
        # Cleanup
        router_proc.terminate()
        router_proc.wait()
        subprocess.run(["pkill", "-f", "http.server"])
        if os.path.exists("/home/user/deployments/dummy.bin"):
            os.remove("/home/user/deployments/dummy.bin")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
