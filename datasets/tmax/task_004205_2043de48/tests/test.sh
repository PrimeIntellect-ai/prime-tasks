#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import subprocess
import tempfile
import textwrap
import uuid

WORKSPACE = "/home/user/workspace"
PROTO = os.path.join(WORKSPACE, "audio_router.proto")
VERIFY = os.path.join(WORKSPACE, "verify_router")
CLEAN = os.path.join(WORKSPACE, "test_corpora/clean_routes.txt")
EVIL = os.path.join(WORKSPACE, "test_corpora/evil_routes.txt")


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def expected_output(clean_path=CLEAN, evil_path=EVIL):
    with open(clean_path) as f:
        clean_count = sum(bool(line.strip()) for line in f)
    with open(evil_path) as f:
        evil_count = sum(bool(line.strip()) for line in f)
    return f"CLEAN_PASSED: {clean_count}\nEVIL_REJECTED: {evil_count}\n"


def test_router_verification_log():
    log_path = os.path.join(WORKSPACE, "router_verification.log")
    assert os.path.isfile(log_path), f"Verification log missing at {log_path}"

    expected = expected_output()
    with open(log_path) as f:
        log_content = f.read()

    for line in expected.splitlines():
        assert line in log_content, f"Log does not contain {line}. Content: {log_content}"


def test_verify_router_is_executable_and_really_runs():
    assert os.path.isfile(VERIFY), f"verify_router missing at {VERIFY}"
    assert os.access(VERIFY, os.X_OK), "verify_router is not executable"

    completed = run([VERIFY], cwd=WORKSPACE, timeout=15)
    assert completed.stderr == "", f"verify_router wrote unexpected stderr: {completed.stderr}"
    assert completed.stdout == expected_output(), (
        f"Unexpected verify_router output: {completed.stdout!r}"
    )

    token = uuid.uuid4().hex
    clean_data = "\n".join([
        "/v3/api/audio/transcribe/wav",
        "/v3/api/audio/transcribe/mp3?lang=en&model=fast",
        "/v3/api/audio/transcribe/flac",
        "/v3/api/audio/analyze/wav?quality=high",
        f"/v3/api/audio/analyze/mp3?request={token}",
        "/v3/api/audio/analyze/flac",
        "/v3/api/audio/metadata/wav",
        "/v3/api/audio/metadata/mp3?key=value",
        "/v3/api/audio/metadata/flac",
    ]) + "\n"
    evil_data = "\n".join([
        "/v3/api/audio/delete/wav",
        "/v3/api/audio/transcribe/ogg",
        "/v2/api/audio/transcribe/wav",
        "/v3/api/audio/../transcribe/wav",
        "/v3/api/audio/transcribe/../wav",
        "/v3/api/audio/transcribe/wav%00",
        "/v3/api/audio/metadata/zip",
        "/v3/api/audio/transcribe",
    ]) + "\n"

    with open(CLEAN, "rb") as f:
        old_clean = f.read()
    with open(EVIL, "rb") as f:
        old_evil = f.read()
    try:
        with open(CLEAN, "w") as f:
            f.write(clean_data)
        with open(EVIL, "w") as f:
            f.write(evil_data)
        completed = run([VERIFY], cwd=WORKSPACE, timeout=15)
        expected = "CLEAN_PASSED: 9\nEVIL_REJECTED: 8\n"
        assert completed.stderr == "", f"verify_router wrote unexpected stderr: {completed.stderr}"
        assert completed.stdout == expected, (
            f"verify_router failed the verifier-supplied corpus: {completed.stdout!r}"
        )
    finally:
        with open(CLEAN, "wb") as f:
            f.write(old_clean)
        with open(EVIL, "wb") as f:
            f.write(old_evil)


def strip_proto_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//.*", "", source)


def test_real_grpc_service_and_routing():
    assert os.path.isfile(PROTO), f"Protobuf definition missing at {PROTO}"
    for path in ("router.h", "router.cpp", "Makefile", "server"):
        assert os.path.exists(os.path.join(WORKSPACE, path)), f"Missing required artifact: {path}"

    with open(PROTO) as f:
        proto_source = strip_proto_comments(f.read())

    package_match = re.search(r"\bpackage\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*;", proto_source)
    package = package_match.group(1) if package_match else ""
    service_match = re.search(r"\bservice\s+AudioRouter\s*\{(.*?)\}", proto_source, re.S)
    assert service_match, "Proto must define service AudioRouter"
    rpc_match = re.search(
        r"\brpc\s+ProcessRequest\s*\(\s*([.]?[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\)"
        r"\s*returns\s*\(\s*([.]?[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\)",
        service_match.group(1), re.S)
    assert rpc_match, "AudioRouter must define unary RPC ProcessRequest"
    request_name, response_name = rpc_match.groups()
    assert request_name.lstrip(".").split(".")[-1] == "ProcessRequest", (
        "The RPC request message must be ProcessRequest, as required by the client API"
    )

    def cpp_type(proto_name):
        if proto_name.startswith("."):
            parts = proto_name[1:].split(".")
        else:
            parts = ([p for p in package.split(".") if p] + proto_name.split("."))
        return "::" + "::".join(parts)

    namespace = "::" + "::".join(package.split(".")) if package else ""
    service_type = f"{namespace}::AudioRouter" if namespace else "::AudioRouter"
    req_type = cpp_type(request_name)
    resp_type = cpp_type(response_name)

    with tempfile.TemporaryDirectory(prefix="audio-router-test-") as td:
        grpc_plugin = subprocess.check_output(["bash", "-lc", "command -v grpc_cpp_plugin"], text=True).strip()
        run(["protoc", f"-I{WORKSPACE}", f"--cpp_out={td}", PROTO])
        run(["protoc", f"-I{WORKSPACE}", f"--grpc_out={td}", f"--plugin=protoc-gen-grpc={grpc_plugin}", PROTO])

        client_source = textwrap.dedent(f'''\
            #include <chrono>
            #include <iostream>
            #include <memory>
            #include <string>
            #include <grpcpp/grpcpp.h>
            #include "audio_router.grpc.pb.h"

            using Request = {req_type};
            using Response = {resp_type};

            int main() {{
              auto channel = grpc::CreateChannel("localhost:50051", grpc::InsecureChannelCredentials());
              if (!channel->WaitForConnected(std::chrono::system_clock::now() + std::chrono::seconds(8))) {{
                std::cerr << "gRPC server did not become ready";
                return 2;
              }}
              auto stub = {service_type}::NewStub(channel);

              auto call = [&](const std::string& route, const std::string& audio,
                              bool accepted, const std::string& result, bool substring) -> bool {{
                Request request;
                Response response;
                request.set_route_path(route);
                request.set_audio_identifier(audio);
                grpc::ClientContext context;
                context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(8));
                grpc::Status status = stub->ProcessRequest(&context, request, &response);
                if (!status.ok()) {{
                  std::cerr << "RPC failed for " << route << ": " << status.error_message();
                  return false;
                }}
                if (response.accepted() != accepted) {{
                  std::cerr << "Wrong accepted value for " << route;
                  return false;
                }}
                if (accepted && !result.empty()) {{
                  bool good = substring ? response.result().find(result) != std::string::npos
                                        : response.result() == result;
                  if (!good) {{
                    std::cerr << "Wrong result for " << route << ": " << response.result();
                    return false;
                  }}
                }}
                return true;
              }};

              if (!call("/v3/api/audio/transcribe/wav", "/app/audio_fixture.wav", true,
                        "Migration to C++ is complete", true)) return 3;
              if (!call("/v3/api/audio/analyze/mp3?quality=high&lang=en", "unused", true, "ok", false)) return 4;
              if (!call("/v3/api/audio/metadata/flac", "unused", true, "ok", false)) return 5;
              if (!call("/v3/api/audio/transcribe/mp3", "unused", true, "ok", false)) return 6;

              if (!call("/v3/api/audio/delete/wav", "unused", false, "", false)) return 10;
              if (!call("/v3/api/audio/transcribe/ogg", "unused", false, "", false)) return 11;
              if (!call("/v2/api/audio/transcribe/wav", "unused", false, "", false)) return 12;
              if (!call("/v3/api/audio/../transcribe/wav", "unused", false, "", false)) return 13;
              if (!call("/v3/api/audio/transcribe/../wav", "unused", false, "", false)) return 14;
              if (!call("/v3/api/audio/transcribe/wav%00", "unused", false, "", false)) return 15;
              std::cout << "OK\\n";
              return 0;
            }}
        ''')
        client_cpp = os.path.join(td, "client.cpp")
        with open(client_cpp, "w") as f:
            f.write(client_source)

        generated_pb = os.path.join(td, "audio_router.pb.cc")
        generated_grpc = os.path.join(td, "audio_router.grpc.pb.cc")
        client_bin = os.path.join(td, "client")
        compile_cmd = (
            f"g++ -std=c++17 -O2 -I{shlex.quote(td)} "
            f"{shlex.quote(client_cpp)} {shlex.quote(generated_pb)} {shlex.quote(generated_grpc)} "
            f"-o {shlex.quote(client_bin)} $(pkg-config --cflags --libs grpc++ protobuf) -pthread"
        )
        run(["bash", "-lc", compile_cmd], timeout=60)
        completed = run([client_bin], timeout=60)
        assert completed.stdout == "OK\n", completed.stdout + completed.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
