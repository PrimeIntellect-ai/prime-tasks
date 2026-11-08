#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import socket
import stat
import subprocess
import textwrap
import time
from pathlib import Path

import pytest

PROJECT_DIR = Path('/home/user/polyglot_calc')
BUILD_SCRIPT = PROJECT_DIR / 'build_and_test.sh'
CLIENT_OUTPUT = Path('/home/user/client_output.txt')
VALGRIND_REPORT = Path('/home/user/valgrind_report.txt')
SERVER = PROJECT_DIR / 'cpp_server/build/calc_server'
RUST_CLIENT = PROJECT_DIR / 'rust_client/target/release/rust_client'


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('stdout', subprocess.PIPE)
    kwargs.setdefault('stderr', subprocess.PIPE)
    return subprocess.run(cmd, **kwargs)


def assert_elf(path):
    assert path.is_file(), f'{path} was not built'
    assert os.access(path, os.X_OK), f'{path} is not executable'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF executable'


def stop_old_servers():
    needle = str(SERVER).encode()
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes()
            if needle in cmdline:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(1)


@pytest.fixture(scope='session', autouse=True)
def execute_requested_build_and_test():
    assert BUILD_SCRIPT.is_file(), f'Build script {BUILD_SCRIPT} does not exist.'
    assert os.stat(BUILD_SCRIPT).st_mode & stat.S_IXUSR, f'Build script {BUILD_SCRIPT} is not executable.'

    stop_old_servers()
    CLIENT_OUTPUT.unlink(missing_ok=True)
    VALGRIND_REPORT.unlink(missing_ok=True)
    shutil.rmtree(PROJECT_DIR / 'cpp_server/build', ignore_errors=True)
    RUST_CLIENT.unlink(missing_ok=True)

    completed = run([str(BUILD_SCRIPT)], cwd=str(PROJECT_DIR), timeout=900)
    assert completed.returncode == 0, (
        f'build_and_test.sh failed with status {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    yield
    stop_old_servers()


def test_build_script_exists_and_executable():
    assert BUILD_SCRIPT.is_file(), f'Build script {BUILD_SCRIPT} does not exist.'
    st = os.stat(BUILD_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f'Build script {BUILD_SCRIPT} is not executable.'


def test_clean_cmake_and_cargo_builds_created_real_binaries():
    assert (PROJECT_DIR / 'cpp_server/build/CMakeCache.txt').is_file(), 'The C++ CMake build directory was not generated.'
    assert_elf(SERVER)
    assert_elf(RUST_CLIENT)


def test_client_output_correct():
    assert CLIENT_OUTPUT.is_file(), f'Client output file {CLIENT_OUTPUT} does not exist. Did build_and_test.sh run?'
    content = CLIENT_OUTPUT.read_text(encoding='utf-8')
    assert '35' in content, f"Expected to find '35' in {CLIENT_OUTPUT}, but got:\n{content}"


def test_valgrind_report_no_leaks():
    assert VALGRIND_REPORT.is_file(), f'Valgrind report {VALGRIND_REPORT} does not exist. Did build_and_test.sh run the server under valgrind?'
    content = VALGRIND_REPORT.read_text(encoding='utf-8', errors='replace')
    match = re.search(r'definitely lost:\s*0 bytes in 0 blocks', content, re.IGNORECASE)
    assert match is not None, f"Expected 'definitely lost: 0 bytes in 0 blocks' in {VALGRIND_REPORT}. Content:\n{content}"


def test_cpp_evaluator_fixed():
    evaluator_file = PROJECT_DIR / 'cpp_server/evaluator.cc'
    assert evaluator_file.is_file(), f'evaluator.cc {evaluator_file} is missing.'
    content = evaluator_file.read_text(encoding='utf-8')
    assert (re.search(r'\*\s*a\s*\*\s*\*\s*b', content)
            or re.search(r'\*\s*b\s*\*\s*\*\s*a', content)
            or 'a * b' in content.replace('*a', 'a').replace('*b', 'b')), \
        'The multiplication logic bug in evaluator.cc does not appear to be fixed.'


def reference_eval(expr):
    stack = []
    for token in expr.split():
        if token in ('+', '*'):
            b = stack.pop()
            a = stack.pop()
            stack.append(a + b if token == '+' else a * b)
        else:
            stack.append(int(token))
    assert len(stack) == 1
    return stack[0]


def test_evaluator_behavior_and_memory_safety(tmp_path):
    expressions = [
        '8 3 *',
        '2 9 + 4 *',
        '7 5 * 6 +',
        '-3 11 * 8 +',
        '1 2 + 3 4 + *',
        '6 2 * 5 * 3 +',
    ]
    harness = tmp_path / 'evaluator_probe.cc'
    harness.write_text(textwrap.dedent(r'''
        #include "evaluator.h"
        #include <iostream>
        int main(int argc, char** argv) {
            for (int i = 1; i < argc; ++i)
                std::cout << evaluate_rpn(argv[i]) << "\n";
            return 0;
        }
    '''), encoding='utf-8')
    binary = tmp_path / 'evaluator_probe'
    compiled = run([
        'g++', '-std=c++17', '-O0', '-g',
        '-I', str(PROJECT_DIR / 'cpp_server'),
        str(harness), str(PROJECT_DIR / 'cpp_server/evaluator.cc'),
        '-o', str(binary),
    ], timeout=120)
    assert compiled.returncode == 0, f'Could not compile evaluator probe:\n{compiled.stderr}'

    report = tmp_path / 'evaluator.valgrind'
    checked = run([
        'valgrind', '--leak-check=full', '--show-leak-kinds=all',
        '--errors-for-leak-kinds=definite', '--error-exitcode=99',
        f'--log-file={report}', str(binary), *expressions,
    ], timeout=120)
    assert checked.returncode == 0, f'Evaluator failed or leaked memory:\n{checked.stderr}\n{report.read_text(errors="replace") if report.exists() else "no report"}'
    actual = [int(line) for line in checked.stdout.splitlines() if line.strip()]
    expected = [reference_eval(expr) for expr in expressions]
    assert actual == expected, f'RPN results were {actual}, expected {expected}'
    report_text = report.read_text(encoding='utf-8', errors='replace')
    assert re.search(r'definitely lost:\s*0 bytes in 0 blocks', report_text, re.I), report_text


def build_grpc_probe(tmp_path):
    proto_dir = PROJECT_DIR / 'proto'
    plugin = shutil.which('grpc_cpp_plugin')
    assert plugin, 'grpc_cpp_plugin is unavailable'
    generated = run([
        'protoc', f'-I{proto_dir}', f'--cpp_out={tmp_path}',
        f'--grpc_out={tmp_path}', f'--plugin=protoc-gen-grpc={plugin}',
        str(proto_dir / 'calc.proto'),
    ], timeout=120)
    assert generated.returncode == 0, generated.stderr

    source = tmp_path / 'probe.cc'
    source.write_text(textwrap.dedent(r'''
        #include <chrono>
        #include <iostream>
        #include <memory>
        #include <string>
        #include <grpcpp/grpcpp.h>
        #include "calc.grpc.pb.h"
        int main(int argc, char** argv) {
            if (argc != 2) return 2;
            auto channel = grpc::CreateChannel("127.0.0.1:50051", grpc::InsecureChannelCredentials());
            if (!channel->WaitForConnected(std::chrono::system_clock::now() + std::chrono::seconds(10))) return 3;
            auto stub = calc::Calculator::NewStub(channel);
            calc::EvalRequest request;
            calc::EvalResponse response;
            grpc::ClientContext context;
            request.set_expression(argv[1]);
            grpc::Status status = stub->Evaluate(&context, request, &response);
            if (!status.ok()) return 4;
            std::cout << response.result() << "\n";
            return 0;
        }
    '''), encoding='utf-8')
    binary = tmp_path / 'grpc_probe'
    command = (
        f"g++ -std=c++17 -O2 -I'{tmp_path}' '{source}' "
        f"'{tmp_path / 'calc.pb.cc'}' '{tmp_path / 'calc.grpc.pb.cc'}' "
        f"$(pkg-config --cflags --libs grpc++ protobuf) -o '{binary}'"
    )
    compiled = run(['bash', '-lc', command], timeout=180)
    assert compiled.returncode == 0, f'Could not compile gRPC probe:\n{compiled.stderr}'
    return binary


def test_built_grpc_service_and_rust_client_really_run(tmp_path):
    stop_old_servers()
    probe = build_grpc_probe(tmp_path)
    server_report = tmp_path / 'server.valgrind'
    server_log = (tmp_path / 'server.log').open('w+')
    process = subprocess.Popen([
        'valgrind', '--leak-check=full', '--show-leak-kinds=all',
        f'--log-file={server_report}', str(SERVER),
    ], stdout=server_log, stderr=subprocess.STDOUT, text=True)
    try:
        deadline = time.time() + 30
        while time.time() < deadline:
            if process.poll() is not None:
                break
            try:
                with socket.create_connection(('127.0.0.1', 50051), timeout=0.25):
                    break
            except OSError:
                time.sleep(0.2)
        else:
            pytest.fail('The built calc_server did not listen on port 50051')
        assert process.poll() is None, 'The built calc_server exited before accepting requests'

        rust = run([str(RUST_CLIENT)], cwd=str(PROJECT_DIR / 'rust_client'), timeout=60)
        assert rust.returncode == 0, f'Built Rust client failed:\n{rust.stdout}\n{rust.stderr}'
        assert re.search(r'(^|\s)35(\s|$)', rust.stdout), f'Rust client did not receive 35:\n{rust.stdout}'

        expressions = ['4 6 * 3 +', '9 2 + 5 *', '-4 7 * 10 +', '2 3 + 4 5 + *']
        for expr in expressions:
            response = run([str(probe), expr], timeout=30)
            assert response.returncode == 0, f'gRPC request for {expr!r} failed:\n{response.stderr}'
            assert response.stdout.strip() == str(reference_eval(expr)), \
                f'Service returned {response.stdout.strip()!r} for {expr!r}'
    finally:
        if process.poll() is None:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        server_log.close()

    assert server_report.is_file(), 'Independent server Valgrind report was not produced'
    report = server_report.read_text(encoding='utf-8', errors='replace')
    assert re.search(r'definitely lost:\s*0 bytes in 0 blocks', report, re.I), report
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
