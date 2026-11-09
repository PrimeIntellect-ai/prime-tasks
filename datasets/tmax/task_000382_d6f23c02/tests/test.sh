#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import os
import secrets
import string
import subprocess
import tempfile

import grpc


def expected_score(payload: str) -> int:
    state = 1
    score = 0
    for c in payload:
        if c in "aeiou":
            state = (state * 2) % 10
        elif "0" <= c <= "9":
            state = (state + ord(c) - ord("0")) % 10
        else:
            state = (state + 1) % 10
        score += ord(c) * state
    return score


def encode_varint(value: int) -> bytes:
    result = bytearray()
    while value >= 0x80:
        result.append((value & 0x7f) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)


def encode_request(payload: str) -> bytes:
    payload_bytes = payload.encode("utf-8")
    return b"\x0a" + encode_varint(len(payload_bytes)) + payload_bytes


def decode_response(data: bytes) -> int:
    # An empty protobuf message is the valid encoding of score=0.
    if not data:
        return 0
    if data[0] != 0x08:
        raise ValueError(f"Invalid response tag/wire-type: {data[0]}")

    value = 0
    shift = 0
    terminated = False
    for b in data[1:]:
        value |= (b & 0x7f) << shift
        if not (b & 0x80):
            terminated = True
            break
        shift += 7
        if shift > 70:
            raise ValueError("Invalid varint")
    if not terminated:
        raise ValueError("Truncated varint")
    if value >= (1 << 31):
        value -= 1 << 32
    return value


def call_library(path: str, payloads):
    library = ctypes.CDLL(path)
    function = library.calculate_risk_score
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_int
    return [function(payload.encode("ascii")) for payload in payloads]


def test_files_exist():
    assert os.path.exists("/home/user/waf.c"), "/home/user/waf.c is missing."
    assert os.path.exists("/home/user/libwaf.so"), "/home/user/libwaf.so is missing."
    assert os.path.exists("/home/user/waf.proto"), "/home/user/waf.proto is missing."
    assert os.path.exists("/home/user/server.py"), "/home/user/server.py is missing."
    assert os.path.exists("/home/user/waf_pb2.py"), "Generated waf_pb2.py is missing."
    assert os.path.exists("/home/user/waf_pb2_grpc.py"), "Generated waf_pb2_grpc.py is missing."


def test_proto_schema():
    with tempfile.TemporaryDirectory() as output_dir:
        subprocess.run(
            [
                "python3", "-m", "grpc_tools.protoc",
                "-I/home/user",
                f"--python_out={output_dir}",
                f"--grpc_python_out={output_dir}",
                "/home/user/waf.proto",
            ],
            check=True,
            timeout=15,
        )
        generated = os.path.join(output_dir, "waf_pb2.py")
        spec = importlib.util.spec_from_file_location("verified_waf_pb2", generated)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        descriptor = module.DESCRIPTOR

        assert descriptor.package == "waf"
        request = descriptor.message_types_by_name["WafRequest"]
        response = descriptor.message_types_by_name["WafResponse"]
        assert len(request.fields) == 1
        assert request.fields[0].name == "payload"
        assert request.fields[0].number == 1
        assert request.fields[0].type == request.fields[0].TYPE_STRING
        assert len(response.fields) == 1
        assert response.fields[0].name == "score"
        assert response.fields[0].number == 1
        assert response.fields[0].type == response.fields[0].TYPE_INT32

        service = descriptor.services_by_name["WafService"]
        assert len(service.methods) == 1
        method = service.methods[0]
        assert method.name == "AnalyzePayload"
        assert method.input_type.full_name == "waf.WafRequest"
        assert method.output_type.full_name == "waf.WafResponse"


def test_running_server_loaded_required_library():
    matching = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                command = handle.read().replace(b"\0", b" ").decode("utf-8", "replace")
            if "server.py" not in command:
                continue
            with open(f"/proc/{entry}/maps", "r", encoding="utf-8", errors="replace") as handle:
                mappings = handle.read()
            if "/home/user/libwaf.so" in mappings:
                matching.append(entry)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    assert matching, "The running server.py process has not loaded /home/user/libwaf.so"


def test_c_source_and_shared_library_implement_algorithm():
    fixed = [
        "",
        "admin' OR 1=1--",
        "<script>alert(1)</script>",
        "test_payload_123",
        "AEIOUxyz019!@#",
        "a0e1i2o3u4Z9",
    ]
    alphabet = string.ascii_letters + string.digits + " _-!'<>/()[]{};:@#$%^&*+=?."
    random_payloads = [
        "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(95) + 1))
        for _ in range(24)
    ]
    payloads = fixed + random_payloads
    expected = [expected_score(payload) for payload in payloads]

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "libwaf_from_source.so")
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", "/home/user/waf.c", "-o", rebuilt],
            check=True,
            timeout=15,
        )
        assert call_library(rebuilt, payloads) == expected

    assert call_library("/home/user/libwaf.so", payloads) == expected


def test_grpc_service_analyze_payload():
    alphabet = string.ascii_letters + string.digits + " _-!'<>/()[]{};:@#$%^&*+=?."
    payloads = [
        "",
        "admin' OR 1=1--",
        "<script>alert(1)</script>",
        "test_payload_123",
        "a0e1i2o3u4Z9",
    ]
    payloads.extend(
        "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(95) + 1))
        for _ in range(24)
    )

    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        analyze_payload = channel.unary_unary(
            "/waf.WafService/AnalyzePayload",
            request_serializer=encode_request,
            response_deserializer=decode_response,
        )
        for payload in payloads:
            score = analyze_payload(payload, timeout=5)
            assert score == expected_score(payload), (
                f"Incorrect score for payload {payload!r}: "
                f"expected {expected_score(payload)}, got {score}"
            )
    finally:
        channel.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
