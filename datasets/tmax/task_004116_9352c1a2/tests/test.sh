#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import subprocess
import sys
import tempfile

import pytest

ANALYZER = "/home/user/audio_tool/analyzer"
PROTO = "/home/user/service/audio.proto"
SERVER = "/home/user/service/server.py"


def test_executable_exists_and_rebuilds():
    assert os.path.isfile(ANALYZER), f"Compiled analyzer executable not found at {ANALYZER}."
    assert os.access(ANALYZER, os.X_OK), f"File at {ANALYZER} is not executable."

    result = subprocess.run(
        ["make", "-B"],
        cwd="/home/user/audio_tool",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"The repaired C project failed to build:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(ANALYZER) and os.access(ANALYZER, os.X_OK)
    with open(ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyzer must be a compiled native executable."

    direct = subprocess.run(
        [ANALYZER, "/app/test_audio.wav"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert direct.returncode == 0, f"analyzer failed when executed directly: {direct.stderr}"
    assert direct.stdout.rstrip("\n") == "EVENTS: 4", (
        f"Expected analyzer output 'EVENTS: 4', got {direct.stdout!r}"
    )


def test_proto_exists():
    assert os.path.isfile(PROTO), f"Protocol Buffers definition not found at {PROTO}."


def test_server_exists():
    assert os.path.isfile(SERVER), f"Python server implementation not found at {SERVER}."


def test_grpc_service_executes_analyzer():
    assert os.path.isfile(PROTO), "audio.proto must exist to test the service."

    try:
        import grpc
    except ImportError:
        pytest.fail("grpc module is not installed. It is required for the gRPC server.")

    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = [
            sys.executable, "-m", "grpc_tools.protoc",
            f"-I{os.path.dirname(PROTO)}",
            f"--python_out={tmpdir}",
            f"--grpc_python_out={tmpdir}",
            PROTO,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Failed to compile proto file using grpc_tools.protoc:\n{result.stderr}"

        sys.path.insert(0, tmpdir)
        channel = None
        try:
            import audio_pb2
            import audio_pb2_grpc

            stub_class = getattr(audio_pb2_grpc, "AudioAnalysisStub", None)
            assert stub_class is not None, "AudioAnalysisStub not found in generated gRPC code."

            service_desc = audio_pb2.DESCRIPTOR.services_by_name.get("AudioAnalysis")
            assert service_desc is not None, "Service 'AudioAnalysis' not found in audio.proto."
            method_desc = service_desc.methods_by_name.get("Analyze")
            assert method_desc is not None, "Method 'Analyze' not found in 'AudioAnalysis' service."

            req_class = getattr(audio_pb2, method_desc.input_type.name)
            channel = grpc.insecure_channel("localhost:50051")
            stub = stub_class(channel)

            try:
                response = stub.Analyze(req_class(file_path="/app/test_audio.wav"), timeout=5)
            except grpc.RpcError as e:
                pytest.fail(f"gRPC call to Analyze failed: {e.details()} (status: {e.code()})")

            assert hasattr(response, "result_text"), "Response message does not have 'result_text' field."
            assert response.result_text == "EVENTS: 4", (
                f"Expected response 'EVENTS: 4', got {response.result_text!r}"
            )

            # Replace the executable temporarily with a runtime probe. A conforming
            # server must invoke this exact path for each request and strip its newline.
            secret = secrets.token_hex(24)
            request_id = secrets.token_hex(12)
            probe_wav = f"/tmp/audio_probe_{request_id}.wav"
            marker = f"/tmp/audio_probe_{secret}.marker"
            backup = f"{ANALYZER}.verifier-backup"
            with open(probe_wav, "wb") as f:
                f.write(b"RIFF....WAVEfmt .....data....")
            os.chmod(probe_wav, 0o644)

            os.replace(ANALYZER, backup)
            try:
                script = (
                    "#!/bin/sh\n"
                    f"printf '%s' \"$1\" > {shlex.quote(marker)}\n"
                    f"printf '%s\\n' {shlex.quote('VERIFIER-PROBE:' + secret)}\n"
                )
                with open(ANALYZER, "w") as f:
                    f.write(script)
                os.chmod(ANALYZER, 0o755)

                try:
                    probed = stub.Analyze(req_class(file_path=probe_wav), timeout=5)
                except grpc.RpcError as e:
                    pytest.fail(f"gRPC probe call failed: {e.details()} (status: {e.code()})")

                assert probed.result_text == f"VERIFIER-PROBE:{secret}", (
                    "Analyze did not return the dynamically installed analyzer's stdout "
                    "with its trailing newline stripped."
                )
                assert os.path.isfile(marker), "The analyzer runtime probe was not executed."
                with open(marker) as f:
                    assert f.read() == probe_wav, "The server did not pass file_path to analyzer unchanged."
            finally:
                if os.path.exists(ANALYZER):
                    os.unlink(ANALYZER)
                os.replace(backup, ANALYZER)
                for path in (probe_wav, marker):
                    try:
                        os.unlink(path)
                    except FileNotFoundError:
                        pass
        finally:
            if channel is not None:
                channel.close()
            sys.path.pop(0)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
