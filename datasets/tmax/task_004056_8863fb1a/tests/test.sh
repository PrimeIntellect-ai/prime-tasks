#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import struct
import subprocess
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

import pytest
import requests

TOKEN = "Bearer TECH-WRITE-2024"
DOC_NAME = "syslog_extract.md"
PLAINTEXT = b"This is the secret markdown documentation.\n# Header\n"
DOC_PATH = Path("/home/user/processed_docs") / DOC_NAME


def test_archive_extraction_and_integrity():
    archive = Path("/home/user/docs_backup.tar.gz")
    wal_path = Path("/home/user/raw_docs/syslog.wal")
    assert archive.is_file(), f"Missing source archive: {archive}"
    assert wal_path.is_file(), f"Extracted WAL not found at {wal_path}"

    with tarfile.open(archive, "r:gz") as tf:
        names = {Path(n).name: n for n in tf.getnames()}
        assert {"part1.zip", "part2.zip", "part3.zip.corrupt"} <= set(names)
        parts = []
        for name in ("part1.zip", "part2.zip", "part3.zip.corrupt"):
            member = tf.extractfile(names[name])
            assert member is not None
            parts.append(member.read())

    assert parts[2].endswith(b"BADEOF"), "Expected corruption marker is absent"
    repaired_zip = parts[0] + parts[1] + parts[2][:-len(b"BADEOF")]
    with tempfile.TemporaryDirectory() as td:
        zip_path = Path(td) / "archive.zip"
        zip_path.write_bytes(repaired_zip)
        with zipfile.ZipFile(zip_path) as zf:
            assert zf.testzip() is None, "Repaired nested ZIP fails integrity testing"
            expected_wal = zf.read("syslog.wal")

    actual_wal = wal_path.read_bytes()
    assert actual_wal == expected_wal, "raw_docs/syslog.wal is not the repaired archive content"
    magic = actual_wal.find(b"\xde\xad\xbe\xef")
    assert magic >= 0 and magic + 8 <= len(actual_wal), "WAL magic/length record is missing"
    payload_len = struct.unpack("<I", actual_wal[magic + 4:magic + 8])[0]
    encrypted = actual_wal[magic + 8:magic + 8 + payload_len]
    assert len(encrypted) == payload_len
    assert bytes(b ^ 0x5A for b in encrypted) == PLAINTEXT


def _run_decoder(binary, args, stdin, cwd):
    try:
        return subprocess.run(
            [binary] + args,
            input=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def test_decoder_script_exists_and_decodes_fresh_input():
    decoder = Path("/home/user/decoder.go")
    assert decoder.is_file(), f"Decoder script not found at {decoder}"

    with tempfile.TemporaryDirectory() as td:
        binary = str(Path(td) / "decoder")
        built = subprocess.run(
            ["go", "build", "-o", binary, str(decoder)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert built.returncode == 0, f"decoder.go does not build: {built.stderr.decode(errors='replace')}"

        plain = b"# Synthetic Decoder Check\nnonce-7f91d2\n"
        cipher = bytes(b ^ 0x5A for b in plain)
        input_path = Path(td) / "cipher.bin"
        output_path = Path(td) / "decoded.md"
        input_path.write_bytes(cipher)

        attempts = [
            ([], cipher),
            ([str(input_path)], None),
            ([str(input_path), str(output_path)], None),
            (["-i", str(input_path), "-o", str(output_path)], None),
        ]
        decoded = False
        for args, stdin in attempts:
            output_path.unlink(missing_ok=True)
            result = _run_decoder(binary, args, stdin, td)
            if result is None or result.returncode != 0:
                continue
            products = [result.stdout]
            if output_path.exists():
                products.append(output_path.read_bytes())
            if any(plain in product for product in products):
                decoded = True
                break
        assert decoded, "The compiled decoder did not XOR-decode fresh wal_parser output"


def test_wal_parser_and_processed_document_content():
    wal = Path("/home/user/raw_docs/syslog.wal").read_bytes()
    parsed = subprocess.run(
        ["/app/bin/wal_parser"],
        input=wal,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert parsed.returncode == 0, "wal_parser failed on the extracted WAL"
    expected_cipher = bytes(b ^ 0x5A for b in PLAINTEXT)
    assert parsed.stdout == expected_cipher, "wal_parser output does not match the WAL record"

    docs_dir = Path("/home/user/processed_docs")
    assert docs_dir.exists(), f"Processed docs directory not found at {docs_dir}"
    assert docs_dir.is_dir(), f"{docs_dir} is not a directory"
    md_files = list(docs_dir.glob("*.md"))
    assert md_files, "No markdown files found in processed_docs directory"
    assert DOC_PATH.is_file(), f"Required processed document missing: {DOC_PATH}"

    content = DOC_PATH.read_bytes()
    assert PLAINTEXT in content, "Processed document does not contain the decoded WAL documentation"
    before, after = content.split(PLAINTEXT, 1)
    added = before + after
    assert added.strip(), "No standard documentation header was added"
    assert re.search(rb"(?m)^#{1,6}\s+\S", added), "Added documentation header is not a Markdown heading"


def test_http_endpoint_unauthorized():
    url = f"http://127.0.0.1:8080/api/v1/docs/{DOC_NAME}"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server on port 8080: {exc}")
    assert response.status_code in (401, 403), \
        f"Expected 401 or 403 for unauthorized request, got {response.status_code}"

    wrong = requests.get(url, headers={"Authorization": "Bearer WRONG"}, timeout=2)
    assert wrong.status_code in (401, 403), "HTTP endpoint accepted an incorrect token"


def test_http_endpoint_authorized_serves_exact_document():
    url = f"http://127.0.0.1:8080/api/v1/docs/{DOC_NAME}"
    try:
        response = requests.get(url, headers={"Authorization": TOKEN}, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server on port 8080: {exc}")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert len(response.text) > 0, "Expected non-empty response body"
    assert response.content == DOC_PATH.read_bytes(), "HTTP response is not the requested processed document"


def test_grpc_port_listening():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(2)
        assert sock.connect_ex(("127.0.0.1", 9090)) == 0, "gRPC server is not listening on port 9090"


def _hpack_int(value, prefix_bits, first):
    limit = (1 << prefix_bits) - 1
    if value < limit:
        return bytes([first | value])
    out = bytearray([first | limit])
    value -= limit
    while value >= 128:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def _hpack_string(value):
    raw = value.encode()
    return _hpack_int(len(raw), 7, 0) + raw


def _literal(name, value):
    return b"\x00" + _hpack_string(name) + _hpack_string(value)


def _frame(frame_type, flags, stream_id, payload=b""):
    length = len(payload)
    return length.to_bytes(3, "big") + bytes([frame_type, flags]) + \
        (stream_id & 0x7fffffff).to_bytes(4, "big") + payload


def _recv_exact(sock, count):
    chunks = []
    while count:
        chunk = sock.recv(count)
        if not chunk:
            raise EOFError
        chunks.append(chunk)
        count -= len(chunk)
    return b"".join(chunks)


def _protobuf_string(field_number, value):
    raw = value.encode()
    tag = (field_number << 3) | 2
    assert tag < 128 and len(raw) < 128
    return bytes([tag, len(raw)]) + raw


def _grpc_call(path, token, request_field=1):
    sock = socket.create_connection(("127.0.0.1", 9090), timeout=2)
    sock.settimeout(2)
    try:
        sock.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + _frame(4, 0, 0))
        headers = bytearray()
        headers += b"\x83"  # :method POST
        headers += b"\x86"  # :scheme http
        headers += _hpack_int(4, 4, 0) + _hpack_string(path)  # :path
        headers += _hpack_int(1, 4, 0) + _hpack_string("127.0.0.1:9090")
        headers += _literal("content-type", "application/grpc")
        headers += _literal("te", "trailers")
        if token is not None:
            headers += _literal("authorization", token)

        proto = _protobuf_string(request_field, DOC_NAME)
        grpc_record = b"\x00" + len(proto).to_bytes(4, "big") + proto
        sock.sendall(_frame(1, 4, 1, bytes(headers)) + _frame(0, 1, 1, grpc_record))

        data = bytearray()
        end_stream = False
        deadline = time.time() + 3
        while time.time() < deadline and not end_stream:
            try:
                header = _recv_exact(sock, 9)
                length = int.from_bytes(header[:3], "big")
                frame_type, flags = header[3], header[4]
                stream_id = int.from_bytes(header[5:], "big") & 0x7fffffff
                payload = _recv_exact(sock, length)
            except (socket.timeout, EOFError):
                break
            if frame_type == 4 and stream_id == 0 and not (flags & 1):
                sock.sendall(_frame(4, 1, 0))
            if stream_id == 1 and frame_type == 0:
                data.extend(payload)
            if stream_id == 1 and (flags & 1):
                end_stream = True

        messages = []
        pos = 0
        while pos + 5 <= len(data):
            compressed = data[pos]
            size = int.from_bytes(data[pos + 1:pos + 5], "big")
            pos += 5
            if pos + size > len(data):
                break
            message = bytes(data[pos:pos + size])
            pos += size
            if compressed == 0:
                messages.append(message)
        return messages
    finally:
        sock.close()


def _grpc_candidates_and_request_field():
    root = Path("/home/user/doc_server")
    assert root.is_dir(), "Go server source directory /home/user/doc_server is missing"
    candidates = []
    request_field = 1
    for path in root.rglob("*"):
        if not path.is_file() or path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        candidates.extend(re.findall(r'FullMethodName\s*=\s*"(/[^"\s]+/GetDocument)"', text))
        candidates.extend("/" + name + "/GetDocument" for name in re.findall(r'ServiceName:\s*"([^"\s]+)"', text))
        if path.suffix == ".proto":
            package_match = re.search(r'\bpackage\s+([\w.]+)\s*;', text)
            package = package_match.group(1) + "." if package_match else ""
            for service in re.findall(r'\bservice\s+(\w+)\s*\{[^}]*\brpc\s+GetDocument\b', text, re.S):
                candidates.append(f"/{package}{service}/GetDocument")
            request = re.search(r'\bmessage\s+DocumentRequest\s*\{(.*?)\}', text, re.S)
            if request:
                field = re.search(r'\bstring\s+(?:filename|name)\s*=\s*(\d+)\s*;', request.group(1))
                if field:
                    request_field = int(field.group(1))

    candidates.extend([
        "/DocumentService/GetDocument",
        "/doc.DocumentService/GetDocument",
        "/docs.DocumentService/GetDocument",
        "/documentation.DocumentService/GetDocument",
        "/DocumentationService/GetDocument",
        "/docs.DocumentationService/GetDocument",
    ])
    return list(dict.fromkeys(candidates)), request_field


def test_grpc_get_document_and_authorization():
    expected = DOC_PATH.read_bytes()
    candidates, request_field = _grpc_candidates_and_request_field()
    successful_path = None
    for path in candidates:
        try:
            messages = _grpc_call(path, TOKEN, request_field)
        except (OSError, AssertionError):
            continue
        if any(expected in message for message in messages):
            successful_path = path
            break
    assert successful_path is not None, \
        "No real gRPC GetDocument method returned the requested processed document"

    unauthorized = _grpc_call(successful_path, None, request_field)
    assert not any(expected in message for message in unauthorized), \
        "gRPC GetDocument returned the document without authorization metadata"
    wrong_token = _grpc_call(successful_path, "Bearer WRONG", request_field)
    assert not any(expected in message for message in wrong_token), \
        "gRPC GetDocument accepted incorrect authorization metadata"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
