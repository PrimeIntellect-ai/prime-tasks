#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import re
import shutil
import signal
import socket
import string
import subprocess
import time
from pathlib import Path

import pytest

SERVICE = Path('/home/user/service')
PROTO = SERVICE / 'api.proto'
MAIN_GO = SERVICE / 'main.go'
RUST_SOURCE = Path('/home/user/formatter/main.rs')
RUST_TOOL = Path('/home/user/formatter/format_tool')
FINAL_RESULT = Path('/home/user/final_result.txt')


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 180)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(map(str, cmd))}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def stop_port_9090():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(':')[-1].upper() == '2382' and fields[3] == '0A':
                inodes.add(fields[9])

    victims = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    victims.add(int(proc.name))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(process):
    deadline = time.time() + 10
    while time.time() < deadline:
        assert process.poll() is None, 'The compiled Go server exited before accepting connections.'
        try:
            with socket.create_connection(('127.0.0.1', 9090), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail('The compiled Go server did not listen on TCP port 9090.')


def expected_process(value):
    return ''.join(chr(ord(ch) + 1) for ch in value[::-1])


@pytest.fixture(scope='session')
def running_submission(tmp_path_factory):
    assert MAIN_GO.is_file(), f'Go server file {MAIN_GO} is missing.'
    assert (SERVICE / 'go.mod').is_file(), 'The Go service has no go.mod and cannot be built reproducibly.'

    build_dir = tmp_path_factory.mktemp('go_verifier')
    server_binary = build_dir / 'migration_server'
    client_binary = build_dir / 'probe_client'

    # Compile the submitted service itself before adding verifier-only sources.
    run(['go', 'build', '-o', str(server_binary), '.'], cwd=SERVICE)
    assert server_binary.is_file() and os.access(server_binary, os.X_OK)

    module_path = run(['go', 'list', '-m', '-f', '{{.Path}}'], cwd=SERVICE).stdout.strip()
    assert module_path and module_path != 'command-line-arguments'

    probe_pkg = SERVICE / 'verifierprobe'
    probe_client = SERVICE / 'verifierclient'
    shutil.rmtree(probe_pkg, ignore_errors=True)
    shutil.rmtree(probe_client, ignore_errors=True)
    probe_pkg.mkdir()
    probe_client.mkdir()
    shutil.copy2(PROTO, probe_pkg / 'api.proto')

    try:
        run([
            'protoc',
            '--go_out=.', '--go_opt=paths=source_relative',
            '--go-grpc_out=.', '--go-grpc_opt=paths=source_relative',
            'verifierprobe/api.proto',
        ], cwd=SERVICE)

        client_source = r'''package main

import (
    "context"
    "encoding/base64"
    "fmt"
    "os"
    "time"

    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
    pb "MODULE_PATH/verifierprobe"
)

func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    conn, err := grpc.DialContext(ctx, "127.0.0.1:9090", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock())
    if err != nil { panic(err) }
    defer conn.Close()
    client := pb.NewMigrationServiceClient(conn)
    for _, encoded := range os.Args[1:] {
        raw, err := base64.StdEncoding.DecodeString(encoded)
        if err != nil { panic(err) }
        callCtx, callCancel := context.WithTimeout(context.Background(), 3*time.Second)
        response, err := client.ProcessString(callCtx, &pb.StringRequest{Payload: string(raw)})
        callCancel()
        if err != nil { panic(err) }
        fmt.Println(base64.StdEncoding.EncodeToString([]byte(response.GetResult())))
    }
}
'''.replace('MODULE_PATH', module_path)
        (probe_client / 'main.go').write_text(client_source)
        run(['go', 'build', '-o', str(client_binary), './verifierclient'], cwd=SERVICE)
    finally:
        shutil.rmtree(probe_pkg, ignore_errors=True)
        shutil.rmtree(probe_client, ignore_errors=True)

    stop_port_9090()
    process = subprocess.Popen(
        [str(server_binary)], cwd=SERVICE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        wait_for_port(process)
        yield client_binary
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)


def test_api_proto_exists():
    assert PROTO.is_file(), f'Protobuf file {PROTO} is missing.'
    content = PROTO.read_text()
    assert 'syntax' in content and 'proto3' in content, "Missing syntax = 'proto3' in proto file."
    assert 'package api;' in content, 'Missing package declaration in proto file.'
    assert 'ProcessString' in content, 'Missing ProcessString RPC method.'
    assert 'StringRequest' in content, 'Missing StringRequest message.'
    assert 'StringResponse' in content, 'Missing StringResponse message.'

    assert re.search(r'syntax\s*=\s*"proto3"\s*;', content)
    assert re.search(r'option\s+go_package\s*=\s*"\./api"\s*;', content)
    assert re.search(r'service\s+MigrationService\s*\{[^}]*rpc\s+ProcessString\s*\(\s*StringRequest\s*\)\s+returns\s*\(\s*StringResponse\s*\)', content, re.S)
    assert re.search(r'message\s+StringRequest\s*\{[^}]*string\s+payload\s*=\s*1\s*;', content, re.S)
    assert re.search(r'message\s+StringResponse\s*\{[^}]*string\s+result\s*=\s*1\s*;', content, re.S)


def test_go_server_exists():
    assert MAIN_GO.is_file(), f'Go server file {MAIN_GO} is missing.'


def test_go_grpc_server_behavior(running_submission):
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + '_- !?@#$%^&*()'
    payloads = ['legacy_python_code', '', '  edge spaces  ']
    payloads.extend(''.join(rng.choice(alphabet) for _ in range(rng.randint(8, 60))) for _ in range(7))

    encoded = [base64.b64encode(value.encode()).decode() for value in payloads]
    result = run([str(running_submission), *encoded], timeout=30)
    lines = result.stdout.splitlines()
    assert len(lines) == len(payloads), f'Expected {len(payloads)} RPC responses, got {len(lines)}.'
    actual = [base64.b64decode(line, validate=True).decode() for line in lines]
    expected = [expected_process(value) for value in payloads]
    assert actual == expected


def test_rust_tool_compiled(tmp_path):
    assert RUST_TOOL.is_file(), f'Compiled Rust tool {RUST_TOOL} is missing.'
    assert os.access(RUST_TOOL, os.X_OK), f'Rust tool {RUST_TOOL} is not executable.'
    assert RUST_TOOL.read_bytes()[:4] == b'\x7fELF', 'format_tool is not a compiled native executable.'
    assert RUST_SOURCE.is_file(), f'Rust source file {RUST_SOURCE} is missing.'

    rebuilt = tmp_path / 'format_tool_rebuilt'
    run(['rustc', str(RUST_SOURCE), '-o', str(rebuilt)])

    rng = random.SystemRandom()
    samples = [
        'hello\n',
        '   already spaced   ',
        '\n\t',
        ''.join(rng.choice(string.ascii_letters + string.digits + ' ') for _ in range(40)) + '\n',
    ]
    for tool in (RUST_TOOL, rebuilt):
        for sample in samples:
            result = subprocess.run([str(tool)], input=sample, text=True, capture_output=True, timeout=10)
            assert result.returncode == 0, result.stderr
            assert result.stdout == f'{sample.strip()} [MIGRATED]\n'


def test_final_result():
    assert FINAL_RESULT.is_file(), f'Final result file {FINAL_RESULT} is missing.'
    original_string = 'legacy_python_code'
    reversed_s = original_string[::-1]
    shifted_s = ''.join(chr(ord(char) + 1) for char in reversed_s)
    expected_result = f'{shifted_s} [MIGRATED]'
    actual_result = FINAL_RESULT.read_text().strip()
    assert actual_result == expected_result, f"Expected final result '{expected_result}', but got '{actual_result}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
