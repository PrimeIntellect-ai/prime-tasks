#!/bin/bash
set -e
mkdir -p /logs/verifier

# The task asks the agent to start this server, so stop any surviving instance
# before binding the verification server to the same required port.
pkill -f '[w]s_server.py' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess
import time


def test_ci_sign_script_exists():
    """Verify that the ci_sign.sh script is present."""
    file_path = "/home/user/ci_sign.sh"
    assert os.path.isfile(file_path), f"File {file_path} is missing. You need to create the Bash script."


def test_websocat_binary_exists_and_executable():
    """Verify that websocat is downloaded and executable."""
    file_path = "/home/user/websocat"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you download websocat?"

    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {file_path} is not executable. You need to run chmod +x on it."

    with open(file_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {file_path} is not a standalone executable binary."


def test_signature_file_content():
    """Verify that the signature.txt file contains the correct signature."""
    file_path = "/home/user/signature.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you save the output?"

    artifact_name = "mobile-release-v2.1.apk"
    expected_checksum = hashlib.sha256(artifact_name.encode("utf-8")).hexdigest()
    expected_signature = f"SIG-{expected_checksum}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_signature, f"The content of {file_path} is incorrect. Expected '{expected_signature}', but got '{content}'."


def test_websocat_and_ci_script_work_on_dynamic_inputs():
    server_source = r'''
import asyncio
import hashlib
import hmac
import json
import os
import websockets

secret = bytes.fromhex(os.environ["VERIFY_SECRET"])
log_path = os.environ["VERIFY_LOG"]
ready_path = os.environ["VERIFY_READY"]

async def handler(websocket, *args):
    try:
        raw = await websocket.recv()
        data = json.loads(raw)
        artifact = data.get("artifact")
        checksum = data.get("checksum")
        if not isinstance(artifact, str):
            await websocket.send(json.dumps({"error": "Invalid artifact"}))
            return
        expected = hashlib.sha256(artifact.encode("utf-8")).hexdigest()
        with open(log_path, "a") as f:
            f.write(json.dumps({"artifact": artifact, "checksum": checksum}) + "\\n")
        if checksum != expected:
            await websocket.send(json.dumps({"error": "Checksum mismatch"}))
            return
        signature = "VERIFY-" + hmac.new(secret, artifact.encode("utf-8"), hashlib.sha256).hexdigest()
        await websocket.send(json.dumps({"status": "success", "signature": signature}))
    except Exception as exc:
        try:
            await websocket.send(json.dumps({"error": str(exc)}))
        except Exception:
            pass

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8765):
        open(ready_path, "w").close()
        await asyncio.Future()

asyncio.run(main())
'''
    server_path = "/tmp/verifier_ws_server.py"
    ready_path = f"/tmp/verifier_ws_ready_{os.getpid()}"
    log_path = f"/tmp/verifier_ws_log_{os.getpid()}"
    marker_path = f"/tmp/verifier_websocat_used_{os.getpid()}"
    secret = secrets.token_bytes(32)

    with open(server_path, "w") as f:
        f.write(server_source)
    open(log_path, "w").close()
    open(marker_path, "w").close()
    os.chmod(marker_path, 0o666)

    env = os.environ.copy()
    env.update({
        "VERIFY_SECRET": secret.hex(),
        "VERIFY_LOG": log_path,
        "VERIFY_READY": ready_path,
    })
    server = subprocess.Popen(["python3", server_path], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    real_websocat = f"/tmp/verifier_websocat_real_{os.getpid()}"
    replaced = False
    try:
        deadline = time.time() + 8
        while not os.path.exists(ready_path) and time.time() < deadline:
            if server.poll() is not None:
                out, err = server.communicate()
                raise AssertionError(f"Verification WebSocket server failed to start: {out} {err}")
            time.sleep(0.05)
        assert os.path.exists(ready_path), "Verification WebSocket server did not become ready."

        # Exercise the submitted standalone client itself, rather than trusting
        # its executable bit.
        direct_artifact = "direct-" + secrets.token_hex(8) + ".bin"
        direct_checksum = hashlib.sha256(direct_artifact.encode("utf-8")).hexdigest()
        direct_signature = "VERIFY-" + __import__("hmac").new(secret, direct_artifact.encode("utf-8"), hashlib.sha256).hexdigest()
        direct_payload = json.dumps({"artifact": direct_artifact, "checksum": direct_checksum}) + "\n"
        direct = subprocess.run(
            ["/home/user/websocat", "-n1", "ws://127.0.0.1:8765"],
            input=direct_payload,
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert direct.returncode == 0, f"websocat failed to communicate with the server: {direct.stderr}"
        direct_response = json.loads(direct.stdout.strip())
        assert direct_response.get("signature") == direct_signature, "websocat did not return the server response."

        # Wrap the submitted binary while testing ci_sign.sh so invocation of
        # the required local websocat is observable; the wrapper delegates all
        # actual communication to the submitted binary.
        os.rename("/home/user/websocat", real_websocat)
        with open("/home/user/websocat", "w") as f:
            f.write("#!/bin/sh\nprintf 'used\\n' >> " + marker_path + "\nexec " + real_websocat + " \"$@\"\n")
        os.chmod("/home/user/websocat", 0o755)
        replaced = True

        artifacts = [
            "dynamic-" + secrets.token_hex(10) + ".apk",
            "name with spaces-" + secrets.token_hex(10) + ".aab",
        ]
        for artifact in artifacts:
            expected_signature = "VERIFY-" + __import__("hmac").new(secret, artifact.encode("utf-8"), hashlib.sha256).hexdigest()
            result = subprocess.run(
                ["bash", "/home/user/ci_sign.sh", artifact],
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, f"ci_sign.sh failed for {artifact!r}: {result.stderr}"
            assert result.stdout.strip() == expected_signature, (
                f"ci_sign.sh did not print the extracted signature for {artifact!r}. "
                f"Got stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

        with open(marker_path) as f:
            uses = [line for line in f if line.strip()]
        assert len(uses) >= len(artifacts), "ci_sign.sh did not use /home/user/websocat for its WebSocket requests."

        with open(log_path) as f:
            requests = [json.loads(line) for line in f if line.strip()]
        for artifact in artifacts:
            matching = [r for r in requests if r.get("artifact") == artifact]
            assert matching, f"The server received no payload for {artifact!r}."
            expected_checksum = hashlib.sha256(artifact.encode("utf-8")).hexdigest()
            assert any(r.get("checksum") == expected_checksum for r in matching), (
                f"The payload for {artifact!r} did not contain its correct SHA-256 checksum."
            )
    finally:
        if replaced:
            try:
                os.unlink("/home/user/websocat")
            except FileNotFoundError:
                pass
            os.rename(real_websocat, "/home/user/websocat")
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
        for path in (ready_path, log_path, marker_path, server_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
