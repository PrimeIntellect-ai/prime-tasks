#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import difflib
import os
import random
import shutil
import string
import struct
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

import grpc
import pytest

ROOTS = [Path('/home/user'), Path('/app')]
OUTPUT = Path('/home/user/decoded_output.txt')
AUDIO = Path('/app/transmission.wav')
EXPECTED = 'HELLOWORLD'


def files_named(name):
    found = []
    for root in ROOTS:
        if root.exists():
            found.extend(p for p in root.rglob(name) if '__pycache__' not in p.parts)
    return found


def python_sources():
    found = []
    for root in ROOTS:
        if root.exists():
            found.extend(p for p in root.rglob('*.py') if '__pycache__' not in p.parts)
    return found


def hamming_encode(text, add_errors=True):
    bits = []
    for byte in text.encode('ascii'):
        for nibble in ((byte >> 4) & 0xF, byte & 0xF):
            d1 = (nibble >> 3) & 1
            d2 = (nibble >> 2) & 1
            d3 = (nibble >> 1) & 1
            d4 = nibble & 1
            block = [0, 0, d1, 0, d2, d3, d4]
            block[0] = block[2] ^ block[4] ^ block[6]
            block[1] = block[2] ^ block[5] ^ block[6]
            block[3] = block[4] ^ block[5] ^ block[6]
            if add_errors:
                block[random.randrange(7)] ^= 1
            bits.extend(str(x) for x in block)
    return ''.join(bits)


def listening_ports():
    ports = set()
    for filename in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(filename).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 3 and fields[3] == '0A':
                ports.add(int(fields[1].rsplit(':', 1)[1], 16))
    return ports


def wait_for_new_port(before, proc):
    deadline = time.time() + 20
    while time.time() < deadline:
        if proc.poll() is not None:
            return None
        new_ports = listening_ports() - before
        if new_ports:
            return sorted(new_ports)[0]
        time.sleep(0.2)
    return None


def make_spoken_wav(message, destination):
    transcript = ' '.join('one' if b == '1' else 'zero' for b in hamming_encode(message, False))
    subprocess.run(
        ['espeak', '-s', '240', '-g', '3', '-w', str(destination), transcript],
        check=True, timeout=90, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def run_client(client, env, expected):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        [sys.executable, str(client)], cwd=str(client.parent), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240
    )
    if result.returncode != 0 or not OUTPUT.is_file():
        return False, result.stdout
    return OUTPUT.read_bytes() == expected.encode('ascii'), result.stdout


@pytest.fixture(scope='session')
def pipeline():
    assert AUDIO.is_file(), 'Missing /app/transmission.wav'
    with wave.open(str(AUDIO), 'rb') as wav:
        assert wav.getnframes() > 0
        frames = wav.readframes(wav.getnframes())
        assert any(frames), 'transmission.wav is silent'

    makefiles = files_named('Makefile') + files_named('makefile')
    relevant = []
    for makefile in makefiles:
        try:
            if 'libhamming' in makefile.read_text(errors='ignore'):
                relevant.append(makefile)
        except OSError:
            pass
    assert relevant, 'No Makefile orchestrating libhamming.so was found'

    built = False
    build_logs = []
    for makefile in relevant:
        result = subprocess.run(
            ['make', '-B', '-f', makefile.name], cwd=str(makefile.parent),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
        )
        build_logs.append(result.stdout)
        if result.returncode == 0 and files_named('libhamming.so'):
            built = True
            break
    assert built, 'Makefile failed to build libhamming.so:\n' + '\n'.join(build_logs)

    libraries = files_named('libhamming.so')
    assert libraries
    for library in libraries:
        assert library.read_bytes()[:4] == b'\x7fELF', f'{library} is not an ELF shared library'

    protos = files_named('processor.proto')
    assert protos, 'processor.proto is missing'
    proto_text = protos[0].read_text(errors='ignore')
    assert 'ProcessPayload' in proto_text and 'PayloadRequest' in proto_text and 'PayloadResponse' in proto_text

    generated = Path(tempfile.mkdtemp(prefix='generated_proto_'))
    result = subprocess.run([
        sys.executable, '-m', 'grpc_tools.protoc',
        f'-I{protos[0].parent}', f'--python_out={generated}', f'--grpc_python_out={generated}',
        str(protos[0])
    ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, 'processor.proto does not compile:\n' + result.stdout

    sys.path.insert(0, str(generated))
    import processor_pb2
    services = list(processor_pb2.DESCRIPTOR.services_by_name.values())
    methods = [m for s in services for m in s.methods if m.name == 'ProcessPayload']
    assert methods, 'Compiled protobuf has no ProcessPayload RPC'
    method = methods[0]
    assert method.input_type.name == 'PayloadRequest'
    assert method.output_type.name == 'PayloadResponse'
    request_fields = [f for f in method.input_type.fields if f.type == f.TYPE_STRING]
    response_fields = [f for f in method.output_type.fields if f.type == f.TYPE_STRING]
    assert request_fields and response_fields, 'Payload messages need string request/response fields'

    sources = python_sources()
    server_candidates = []
    client_candidates = []
    for source in sources:
        text = source.read_text(errors='ignore')
        if 'ProcessPayload' in text and 'grpc.server' in text and 'ctypes' in text and ('CDLL' in text or 'libhamming.so' in text):
            server_candidates.append(source)
        if 'transmission.wav' in text and 'decoded_output.txt' in text and 'grpc' in text:
            client_candidates.append(source)
    assert server_candidates, 'No Python gRPC server using ctypes/libhamming.so was found'
    assert client_candidates, 'No integration client reading the audio and writing decoded_output.txt was found'

    source_dirs = sorted({str(p.parent) for p in sources})
    env = os.environ.copy()
    env['PYTHONPATH'] = os.pathsep.join([str(generated)] + source_dirs + [env.get('PYTHONPATH', '')])

    server_proc = None
    port = None
    chosen_server = None
    for server in server_candidates:
        before = listening_ports()
        proc = subprocess.Popen(
            [sys.executable, str(server)], cwd=str(server.parent), env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        candidate_port = wait_for_new_port(before, proc)
        if candidate_port is not None:
            server_proc, port, chosen_server = proc, candidate_port, server
            break
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
    assert server_proc is not None, 'The gRPC server could not be started or did not listen on a TCP port'

    channel = grpc.insecure_channel(f'127.0.0.1:{port}')
    grpc.channel_ready_future(channel).result(timeout=10)
    rpc_path = f'/{method.containing_service.full_name}/{method.name}'
    call = channel.unary_unary(
        rpc_path,
        request_serializer=lambda value: value.SerializeToString(),
        response_deserializer=method.output_type._concrete_class.FromString,
    )

    try:
        for _ in range(4):
            expected = ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(random.randint(2, 9)))
            request = method.input_type._concrete_class()
            setattr(request, request_fields[0].name, hamming_encode(expected, True))
            response = call(request, timeout=10)
            assert getattr(response, response_fields[0].name) == expected, 'gRPC/C Hamming decoding failed on a derived payload with one-bit errors'

        original_audio = AUDIO.read_bytes()
        alternate = ''.join(random.choice(string.ascii_uppercase + string.digits) for _ in range(3))
        try:
            make_spoken_wav(alternate, AUDIO)
            selected_client = None
            diagnostics = []
            for client in client_candidates:
                ok, output = run_client(client, env, alternate)
                diagnostics.append(f'{client}: {output[-1000:]}')
                if ok:
                    selected_client = client
                    break
            assert selected_client is not None, 'No client transcribed and decoded a verifier-generated audio payload:\n' + '\n'.join(diagnostics)
        finally:
            AUDIO.write_bytes(original_audio)

        ok, output = run_client(selected_client, env, EXPECTED)
        assert ok, 'The client failed end-to-end on the provided transmission:\n' + output[-2000:]
        yield
    finally:
        channel.close()
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_proc.kill()
        shutil.rmtree(generated, ignore_errors=True)


def test_decoded_output_accuracy(pipeline):
    output_file = '/home/user/decoded_output.txt'
    expected = 'HELLOWORLD'

    assert os.path.exists(output_file), f'Output file is missing at {output_file}'
    assert os.path.isfile(output_file), f'Path {output_file} is not a file'

    with open(output_file, 'r') as f:
        actual = f.read().strip()

    ratio = difflib.SequenceMatcher(None, expected, actual).ratio()
    assert ratio >= 0.9, (
        f'Decoded output does not meet the accuracy threshold. '
        f'Expected at least 0.9, got {ratio:.4f}. '
        f"Expected string: '{expected}', Actual string: '{actual}'"
    )
    assert Path(output_file).read_bytes() == b'HELLOWORLD', 'Output must contain only the decoded string with no trailing data'
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
