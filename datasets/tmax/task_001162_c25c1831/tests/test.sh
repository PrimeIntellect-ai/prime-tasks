#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import socket
import subprocess
import tempfile
from functools import lru_cache

import grpc
import pytest
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

PROTO_PATH = "/home/user/artifact.proto"
CRT_PATH = "/home/user/certs/server.crt"
KEY_PATH = "/home/user/certs/server.key"
JSON_PATH = "/home/user/tls_overhead.json"


def run_checked(args, **kwargs):
    result = subprocess.run(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command {' '.join(args)} failed: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


@lru_cache(maxsize=1)
def parsed_schema():
    assert os.path.isfile(PROTO_PATH), f"File {PROTO_PATH} does not exist."
    with open(PROTO_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert "package build;" in content, "Proto file is missing 'package build;'"
    assert "service ArtifactCache" in content, "Proto file is missing 'service ArtifactCache'"
    assert "rpc GetChecksum" in content, "Proto file is missing 'rpc GetChecksum'"
    assert "ArtifactRequest" in content, "Proto file is missing 'ArtifactRequest'"
    assert "ArtifactResponse" in content, "Proto file is missing 'ArtifactResponse'"

    with tempfile.TemporaryDirectory() as td:
        descriptor_path = os.path.join(td, "artifact.desc")
        result = subprocess.run(
            [
                "python3", "-m", "grpc_tools.protoc",
                "-I/home/user",
                f"--descriptor_set_out={descriptor_path}",
                "--include_imports",
                PROTO_PATH,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            "artifact.proto is not a valid compilable Protocol Buffer definition: "
            + result.stderr.decode(errors="replace")
        )
        descriptor_set = descriptor_pb2.FileDescriptorSet()
        with open(descriptor_path, "rb") as f:
            descriptor_set.ParseFromString(f.read())

    artifact_files = [fd for fd in descriptor_set.file if fd.name.endswith("artifact.proto")]
    assert len(artifact_files) == 1, "Could not uniquely identify artifact.proto descriptor"
    fd = artifact_files[0]
    assert fd.package == "build", "Proto package must be exactly 'build'"

    services = [s for s in fd.service if s.name == "ArtifactCache"]
    assert len(services) == 1, "Proto must define exactly one ArtifactCache service"
    service = services[0]
    assert len(service.method) == 1, "ArtifactCache must contain a single RPC method"
    method = service.method[0]
    assert method.name == "GetChecksum", "ArtifactCache's RPC must be GetChecksum"
    assert method.input_type == ".build.ArtifactRequest"
    assert method.output_type == ".build.ArtifactResponse"
    assert not method.client_streaming and not method.server_streaming, "GetChecksum must be unary"

    messages = {m.name: m for m in fd.message_type}
    assert "ArtifactRequest" in messages and "ArtifactResponse" in messages
    request_fields = list(messages["ArtifactRequest"].field)
    response_fields = list(messages["ArtifactResponse"].field)
    assert len(request_fields) == 1, "ArtifactRequest must contain only filename"
    assert request_fields[0].name == "filename", "ArtifactRequest field must be filename"
    assert request_fields[0].type == request_fields[0].TYPE_STRING, "filename must be a string"
    assert not request_fields[0].label == request_fields[0].LABEL_REPEATED
    assert len(response_fields) == 1, "ArtifactResponse must contain only checksum"
    assert response_fields[0].name == "checksum", "ArtifactResponse field must be checksum"
    assert response_fields[0].type == response_fields[0].TYPE_STRING, "checksum must be a string"
    assert not response_fields[0].label == response_fields[0].LABEL_REPEATED

    pool = descriptor_pool.DescriptorPool()
    for file_descriptor in descriptor_set.file:
        pool.Add(file_descriptor)
    request_cls = message_factory.GetMessageClass(
        pool.FindMessageTypeByName("build.ArtifactRequest")
    )
    response_cls = message_factory.GetMessageClass(
        pool.FindMessageTypeByName("build.ArtifactResponse")
    )
    return request_cls, response_cls


def test_proto_file():
    parsed_schema()


def test_certs_exist():
    assert os.path.isfile(CRT_PATH), f"Certificate file {CRT_PATH} does not exist."
    assert os.path.isfile(KEY_PATH), f"Key file {KEY_PATH} does not exist."

    run_checked(["openssl", "x509", "-in", CRT_PATH, "-noout", "-checkend", "0"])
    run_checked(["openssl", "rsa", "-in", KEY_PATH, "-check", "-noout"])
    run_checked(["openssl", "verify", "-CAfile", CRT_PATH, CRT_PATH])
    run_checked(["openssl", "verify", "-verify_hostname", "localhost", "-CAfile", CRT_PATH, CRT_PATH])

    cert_text = run_checked(["openssl", "x509", "-in", CRT_PATH, "-noout", "-text"]).decode()
    assert "Public Key Algorithm: rsaEncryption" in cert_text, "Certificate must use RSA"
    assert "Public-Key: (2048 bit)" in cert_text, "Certificate RSA key must be 2048-bit"

    subject = run_checked(["openssl", "x509", "-in", CRT_PATH, "-noout", "-subject", "-nameopt", "RFC2253"])
    issuer = run_checked(["openssl", "x509", "-in", CRT_PATH, "-noout", "-issuer", "-nameopt", "RFC2253"])
    assert subject.replace(b"subject=", b"", 1).strip() == issuer.replace(b"issuer=", b"", 1).strip(), (
        "Certificate must be self-signed"
    )

    cert_public_pem = run_checked(["openssl", "x509", "-in", CRT_PATH, "-pubkey", "-noout"])
    cert_public_der = run_checked(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_public_pem
    )
    key_public_der = run_checked(
        ["openssl", "pkey", "-in", KEY_PATH, "-pubout", "-outform", "DER"]
    )
    assert cert_public_der == key_public_der, "Certificate and private key do not match"


@lru_cache(maxsize=1)
def execute_benchmarks():
    request_cls, response_cls = parsed_schema()
    with open(CRT_PATH, "rb") as f:
        trusted_cert = f.read()

    plaintext_channel = grpc.insecure_channel("127.0.0.1:50051")
    tls_channel = grpc.secure_channel(
        "127.0.0.1:50052",
        grpc.ssl_channel_credentials(root_certificates=trusted_cert),
        options=(("grpc.ssl_target_name_override", "localhost"),),
    )
    try:
        grpc.channel_ready_future(plaintext_channel).result(timeout=5)
        grpc.channel_ready_future(tls_channel).result(timeout=5)

        plaintext_call = plaintext_channel.unary_unary(
            "/build.ArtifactCache/GetChecksum",
            request_serializer=lambda value: value.SerializeToString(),
            response_deserializer=response_cls.FromString,
        )
        tls_call = tls_channel.unary_unary(
            "/build.ArtifactCache/GetChecksum",
            request_serializer=lambda value: value.SerializeToString(),
            response_deserializer=response_cls.FromString,
        )

        import time
        start = time.perf_counter()
        for i in range(1000):
            response = plaintext_call(request_cls(filename=f"plain-{i}"), timeout=3)
            assert response.checksum == "sha256:dummy", (
                "Plaintext GetChecksum returned an incorrect checksum"
            )
        plaintext_elapsed = time.perf_counter() - start

        start = time.perf_counter()
        for i in range(1000):
            response = tls_call(request_cls(filename=f"tls-{i}"), timeout=3)
            assert response.checksum == "sha256:dummy", (
                "TLS GetChecksum returned an incorrect checksum"
            )
        tls_elapsed = time.perf_counter() - start
    finally:
        plaintext_channel.close()
        tls_channel.close()

    assert plaintext_elapsed > 0 and tls_elapsed > 0
    plaintext_rps = 1000.0 / plaintext_elapsed
    tls_rps = 1000.0 / tls_elapsed
    overhead = ((plaintext_rps - tls_rps) / plaintext_rps) * 100.0
    return plaintext_rps, tls_rps, overhead


def test_grpc_endpoints_and_exact_request_counts():
    # This performs exactly 1000 sequential RPCs against each endpoint, validates
    # protobuf responses, and proves that port 50052 is usable through TLS.
    execute_benchmarks()


def test_json_output():
    assert os.path.exists(JSON_PATH), f"File {JSON_PATH} does not exist."
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "plaintext_rps" in data, "JSON missing 'plaintext_rps'"
    assert "tls_rps" in data, "JSON missing 'tls_rps'"
    assert "overhead_percentage" in data, "JSON missing 'overhead_percentage'"
    assert set(data) == {"plaintext_rps", "tls_rps", "overhead_percentage"}, (
        "JSON must use exactly the required result fields"
    )

    for key in data:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), (
            f"{key} must be numeric"
        )
        assert math.isfinite(float(data[key])), f"{key} must be finite"

    pt = float(data["plaintext_rps"])
    tls = float(data["tls_rps"])
    overhead = float(data["overhead_percentage"])
    assert pt > 0, "plaintext_rps must be positive"
    assert tls > 0, "tls_rps must be positive"

    expected_overhead = ((pt - tls) / pt) * 100
    assert math.isclose(overhead, expected_overhead, rel_tol=0.01, abs_tol=0.01), (
        f"overhead_percentage {overhead} does not match expected {expected_overhead}"
    )

    measured_pt, measured_tls, measured_overhead = execute_benchmarks()
    assert 0.25 <= pt / measured_pt <= 4.0, "Reported plaintext_rps is not plausible"
    assert 0.25 <= tls / measured_tls <= 4.0, "Reported tls_rps is not plausible"
    assert abs(overhead - measured_overhead) <= 25.0, (
        "Reported TLS overhead is inconsistent with an independent 1000-request benchmark"
    )


def test_ports_in_use():
    for port in [50051, 50052]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1.0)
            result = s.connect_ex(("127.0.0.1", port))
            assert result == 0, f"Port {port} is not listening. The gRPC server must be running."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
