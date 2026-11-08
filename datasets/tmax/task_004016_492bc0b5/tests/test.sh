#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def test_system_proto_exists_and_valid():
    proto_path = "/home/user/system.proto"
    assert os.path.isfile(proto_path), f"File {proto_path} does not exist."
    with open(proto_path, "r") as f:
        content = f.read()
    assert "syntax" in content and "proto3" in content, "system.proto must use proto3 syntax."
    assert "service System" in content, "system.proto must define 'service System'."
    assert "rpc GetStatus" in content, "system.proto must define 'rpc GetStatus'."


def test_nginx_conf_configured_for_grpc():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read()
    assert "daemon off" in content, "nginx.conf must run in the foreground (daemon off)."
    assert "8080" in content, "nginx.conf must listen on port 8080."
    assert "http2" in content, "nginx.conf must use HTTP/2 for gRPC."
    assert "grpc_pass" in content and "127.0.0.1:50051" in content, "nginx.conf must forward gRPC traffic to 127.0.0.1:50051."


def test_update_patch_exists():
    patch_path = "/home/user/update.patch"
    assert os.path.isfile(patch_path), f"Patch file {patch_path} does not exist."


def test_check_system_script_patched():
    script_path = "/home/user/check_system.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    with open(script_path, "r") as f:
        content = f.read()
    assert "grpcurl" in content, "check_system.sh must use grpcurl."
    assert "-proto /home/user/system.proto" in content, "grpcurl must use the -proto flag with the proto file."
    assert "-plaintext" in content, "grpcurl must use the -plaintext flag."
    assert "8080" in content, "grpcurl must target the Nginx proxy on port 8080."


def test_success_log_contains_expected_output():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you redirect the output?"
    with open(log_path, "r") as f:
        content = f.read()
    assert "ALL_SYSTEMS_NOMINAL" in content, "success.log does not contain the expected gRPC response."


def apply_unified_patch(original, patch_text):
    lines = patch_text.splitlines(keepends=True)
    header = next((i for i, line in enumerate(lines) if line.startswith("--- ")), None)
    assert header is not None and header + 1 < len(lines), "update.patch is not a unified diff."
    assert lines[header + 1].startswith("+++ "), "update.patch is missing its new-file header."
    assert not any(line.startswith("--- ") for line in lines[header + 2:]), "update.patch must modify only check_system.sh."

    old = original.splitlines(keepends=True)
    result = []
    old_pos = 0
    i = header + 2
    saw_hunk = False
    hunk_re = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")

    while i < len(lines):
        if not lines[i].startswith("@@ "):
            assert lines[i].strip() == "", "Unexpected data outside a unified-diff hunk."
            i += 1
            continue
        match = hunk_re.match(lines[i])
        assert match, "Malformed unified-diff hunk header."
        saw_hunk = True
        old_start = int(match.group(1))
        old_count = int(match.group(2) or "1")
        new_count = int(match.group(4) or "1")
        target_pos = old_start - 1
        assert target_pos >= old_pos and target_pos <= len(old), "Patch hunk is outside the legacy script."
        result.extend(old[old_pos:target_pos])
        old_pos = target_pos
        used_old = used_new = 0
        i += 1

        while used_old < old_count or used_new < new_count:
            assert i < len(lines), "Truncated unified-diff hunk."
            line = lines[i]
            if line.startswith("\\ No newline at end of file"):
                i += 1
                continue
            assert line and line[0] in " +-", "Malformed unified-diff hunk line."
            marker, payload = line[0], line[1:]
            if marker in " -":
                assert old_pos < len(old) and old[old_pos] == payload, "Patch does not apply to the original legacy script."
                old_pos += 1
                used_old += 1
            if marker in " +":
                result.append(payload)
                used_new += 1
            i += 1
        assert used_old == old_count and used_new == new_count, "Patch hunk line counts are invalid."

    assert saw_hunk, "update.patch contains no changes."
    result.extend(old[old_pos:])
    return "".join(result)


def wait_for_port(port, process, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Process exited before port {port} became ready.")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for port {port}.")


def test_patch_proto_proxy_and_script_work_end_to_end():
    legacy = '#!/bin/bash\necho "Checking system status..."\ncurl -s http://api.legacy.local/v1/status\n'
    with open("/home/user/update.patch", "r") as f:
        patch_text = f.read()
    with open("/home/user/check_system.sh", "r") as f:
        installed_script = f.read()
    assert apply_unified_patch(legacy, patch_text) == installed_script, \
        "Applying update.patch to the original legacy script must reproduce check_system.sh."

    with tempfile.TemporaryDirectory(prefix="verify_grpc_") as tmp:
        compile_result = subprocess.run(
            [sys.executable, "-m", "grpc_tools.protoc", "-I/home/user", f"--python_out={tmp}",
             f"--grpc_python_out={tmp}", "/home/user/system.proto"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert compile_result.returncode == 0, f"system.proto does not compile:\n{compile_result.stderr}"

        sys.path.insert(0, tmp)
        try:
            import system_pb2 as pb
            import system_pb2_grpc as pb_grpc
            service = pb.DESCRIPTOR.services_by_name.get("System")
            assert service is not None and service.full_name == "System", "The server expects service System with no package prefix."
            assert len(service.methods) == 1 and service.methods[0].name == "GetStatus", "System must expose GetStatus."
            method = service.methods[0]
            assert method.input_type.full_name == "StatusRequest", "GetStatus must accept StatusRequest."
            assert method.output_type.full_name == "StatusResponse", "GetStatus must return StatusResponse."
            status_field = method.output_type.fields_by_name.get("status")
            assert status_field is not None and status_field.number == 1 and status_field.type == status_field.TYPE_STRING, \
                "StatusResponse must contain string status = 1."
        finally:
            sys.path.pop(0)

        token = "VERIFIER_" + secrets.token_hex(16)
        server_source = f'''\nimport os, sys, grpc\nfrom concurrent import futures\nsys.path.insert(0, {tmp!r})\nimport system_pb2 as pb\nimport system_pb2_grpc as pb_grpc\nclass Servicer(pb_grpc.SystemServicer):\n    def GetStatus(self, request, context):\n        return pb.StatusResponse(status=os.environ["VERIFY_TOKEN"])\nserver = grpc.server(futures.ThreadPoolExecutor(max_workers=2))\npb_grpc.add_SystemServicer_to_server(Servicer(), server)\nserver.add_insecure_port("127.0.0.1:50051")\nserver.start()\nserver.wait_for_termination()\n'''
        server_file = os.path.join(tmp, "dynamic_server.py")
        with open(server_file, "w") as f:
            f.write(server_source)

        subprocess.run(["pkill", "-f", "/home/user/mock_server.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.2)

        syntax = subprocess.run(["nginx", "-t", "-c", "/home/user/nginx.conf"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert syntax.returncode == 0, f"nginx.conf is not valid:\n{syntax.stdout}\n{syntax.stderr}"

        env = os.environ.copy()
        env["VERIFY_TOKEN"] = token
        server_proc = subprocess.Popen([sys.executable, server_file], env=env,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        nginx_proc = None
        real_grpcurl = "/usr/local/bin/grpcurl"
        backup_grpcurl = real_grpcurl + ".verifier-" + secrets.token_hex(8)
        call_log = os.path.join(tmp, "grpcurl.calls")
        wrapped = False
        try:
            wait_for_port(50051, server_proc)
            nginx_proc = subprocess.Popen(["nginx", "-c", "/home/user/nginx.conf"],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            wait_for_port(8080, nginx_proc)

            assert os.path.isfile(real_grpcurl), "grpcurl is unavailable."
            os.replace(real_grpcurl, backup_grpcurl)
            with open(real_grpcurl, "w") as f:
                f.write(f'''#!/bin/bash\n{{ printf 'CALL\\0'; printf '%s\\0' "$@"; printf 'END\\0'; }} >> {call_log!r}\nexec {backup_grpcurl!r} "$@"\n''')
            os.chmod(real_grpcurl, 0o755)
            wrapped = True

            run = subprocess.run(["/bin/bash", "/home/user/check_system.sh"],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            assert run.returncode == 0, f"check_system.sh failed:\n{run.stdout}\n{run.stderr}"
            assert token in run.stdout, "The script did not print the live gRPC server's response through Nginx."
            assert os.path.isfile(call_log), "check_system.sh did not execute grpcurl."

            entries = open(call_log, "rb").read().split(b"\0")
            calls = []
            current = None
            for entry in entries:
                value = entry.decode("utf-8", errors="replace")
                if value == "CALL":
                    current = []
                elif value == "END" and current is not None:
                    calls.append(current)
                    current = None
                elif current is not None and value:
                    current.append(value)

            def valid_call(args):
                return ("-plaintext" in args and
                        any(args[i] == "-proto" and i + 1 < len(args) and args[i + 1] == "/home/user/system.proto"
                            for i in range(len(args))) and
                        "localhost:8080" in args and "System/GetStatus" in args)

            assert any(valid_call(args) for args in calls), \
                "grpcurl must use -proto /home/user/system.proto, -plaintext, localhost:8080, and System/GetStatus."
        finally:
            if wrapped:
                try:
                    os.remove(real_grpcurl)
                except FileNotFoundError:
                    pass
                if os.path.exists(backup_grpcurl):
                    os.replace(backup_grpcurl, real_grpcurl)
            if nginx_proc is not None and nginx_proc.poll() is None:
                nginx_proc.terminate()
                try:
                    nginx_proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    nginx_proc.kill()
            subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if server_proc.poll() is None:
                server_proc.terminate()
                try:
                    server_proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server_proc.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
