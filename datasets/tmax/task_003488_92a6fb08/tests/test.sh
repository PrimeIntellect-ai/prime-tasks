#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import math
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import time

import grpc
import numpy as np
import pytest
from scipy.special import expit

SERVICE = pathlib.Path('/home/user/service')
LIBDIR = pathlib.Path('/app/libfastcalc-1.2.3')
BUILD = pathlib.Path('/tmp/fastcalc_verifier_build')
MARKER = pathlib.Path('/tmp/fastcalc_library_called')
SERVER_PROCESS = None


def run(cmd, **kwargs):
    result = subprocess.run(cmd, text=True, capture_output=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(map(str, cmd))}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def stop_port_50051():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            cols = line.split()
            if len(cols) >= 10 and cols[1].rsplit(':', 1)[-1].upper() == 'C383' and cols[3] == '0A':
                inodes.add(cols[9])

    victims = set()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m and m.group(1) in inodes:
                    victims.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def generated_message_class(pb2, descriptor):
    short_name = descriptor.full_name.rsplit('.', 1)[-1]
    cls = getattr(pb2, short_name, None)
    if cls is not None:
        return cls
    from google.protobuf import symbol_database
    return symbol_database.Default().GetSymbol(descriptor.full_name)


@pytest.fixture(scope='session')
def built_service():
    global SERVER_PROCESS

    proto = SERVICE / 'calc.proto'
    server = SERVICE / 'server.cc'
    client = SERVICE / 'test_client.py'
    makefile = LIBDIR / 'Makefile'
    source = LIBDIR / 'fastcalc.c'
    header = LIBDIR / 'fastcalc.h'

    # Preserve the original existence assertion and check every requested artifact.
    assert proto.exists(), 'calc.proto is missing'
    assert server.is_file(), 'server.cc is missing'
    assert client.is_file(), 'test_client.py is missing'
    assert makefile.is_file(), 'libfastcalc Makefile is missing'
    assert source.is_file(), 'fastcalc.c is missing'
    assert header.is_file(), 'fastcalc.h is missing'

    server_text = server.read_text(errors='replace')
    assert re.search(r'#\s*include\s*[<\"]fastcalc\.h[>\"]', server_text), 'server.cc must include fastcalc.h'
    assert re.search(r'\bfast_sigmoid_array\s*\(', server_text), 'server.cc must call fast_sigmoid_array'
    assert re.search(r'\bFASTCALC_VERSION\b', server_text), 'server.cc must return the version from fastcalc.h'

    client_text = client.read_text(errors='replace')
    assert 'localhost:50051' in client_text or '127.0.0.1:50051' in client_text, 'test_client.py must connect to localhost:50051'
    assert 'GetVersion' in client_text and 'ComputeSigmoid' in client_text, 'test_client.py must exercise both RPCs'
    assert 'linspace' in client_text and '10000' in client_text and '-10' in client_text and '10' in client_text, 'test_client.py must send 10,000 linearly spaced values from -10 to 10'
    try:
        client_tree = ast.parse(client_text)
    except SyntaxError as exc:
        pytest.fail(f'test_client.py is not valid Python: {exc}')
    exact_version_assert = False
    for node in ast.walk(client_tree):
        if isinstance(node, ast.Assert):
            segment = ast.get_source_segment(client_text, node.test) or ''
            if '1.2.3' in segment and ('==' in segment or '!=' in segment):
                exact_version_assert = True
                break
    assert exact_version_assert, 'test_client.py must assert that the returned version is exactly "1.2.3"'

    if BUILD.exists():
        shutil.rmtree(BUILD)
    BUILD.mkdir(parents=True)

    # Rebuild the submitted C library and verify that its actual compile command uses PIC.
    run(['make', 'clean'], cwd=LIBDIR)
    make_result = run(['make', 'V=1'], cwd=LIBDIR)
    build_log = make_result.stdout + '\n' + make_result.stderr
    compile_lines = [line for line in build_log.splitlines() if 'fastcalc.c' in line and (' -c ' in f' {line} ' or '\t-c ' in line)]
    assert compile_lines, f'Could not find the fastcalc.c compile command in make output:\n{build_log}'
    assert any(re.search(r'(^|\s)-fPIC(\s|$)', line) for line in compile_lines), 'The Makefile must compile fastcalc.c with -fPIC'
    archive = LIBDIR / 'libfastcalc.a'
    obj = LIBDIR / 'fastcalc.o'
    assert archive.is_file() and obj.is_file(), 'Makefile did not produce libfastcalc.a and fastcalc.o'
    members = run(['ar', 't', str(archive)]).stdout.splitlines()
    assert 'fastcalc.o' in members, 'libfastcalc.a does not contain fastcalc.o'

    # PIC must be usable in a shared object, and the submitted C implementation itself must be accurate.
    shared = BUILD / 'libfastcalc_check.so'
    run(['gcc', '-shared', '-o', str(shared), str(obj), '-lm'])
    c_lib = ctypes.CDLL(str(shared))
    c_func = c_lib.fast_sigmoid_array
    c_func.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    c_func.restype = None

    rng = np.random.default_rng(0xFAC123)
    c_inputs = np.concatenate((
        np.linspace(-10.0, 10.0, 10000),
        rng.uniform(-10.0, 10.0, 4093),
        np.array([-10.0, -9.999, -1.0, -0.0, 0.0, 1.0, 9.999, 10.0]),
    )).astype(np.float64)
    c_outputs = np.empty_like(c_inputs)
    c_func(
        c_inputs.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        c_outputs.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
        len(c_inputs),
    )
    assert np.all(np.isfinite(c_outputs)), 'fast_sigmoid_array returned non-finite values'
    c_mse = float(np.mean((c_outputs - expit(c_inputs)) ** 2))
    assert c_mse < 1e-4, f'fast_sigmoid_array MSE {c_mse} is not less than 1e-4'

    protoc = shutil.which('protoc')
    plugin = shutil.which('grpc_cpp_plugin')
    assert protoc and plugin, 'C++ protobuf/gRPC compiler tools are unavailable'
    run([
        protoc, f'-I{SERVICE}', f'--cpp_out={BUILD}', f'--grpc_out={BUILD}',
        f'--plugin=protoc-gen-grpc={plugin}', str(proto),
    ])
    # Keep the original Python-proto compilation assertion.
    run([
        sys.executable, '-m', 'grpc_tools.protoc', f'-I{SERVICE}',
        f'--python_out={BUILD}', f'--grpc_python_out={BUILD}', str(proto),
    ])

    wrapper = BUILD / 'call_wrapper.cc'
    wrapper.write_text(r'''
#include <cstdio>
extern "C" void __real_fast_sigmoid_array(const double*, double*, int);
extern "C" void __wrap_fast_sigmoid_array(const double* in, double* out, int length) {
    __real_fast_sigmoid_array(in, out, length);
    FILE* f = std::fopen("/tmp/fastcalc_library_called", "a");
    if (f) { std::fputs("called\n", f); std::fclose(f); }
}
''')

    pkg = run(['pkg-config', '--cflags', '--libs', 'grpc++', 'protobuf']).stdout.split()
    binary = BUILD / 'fastcalc_server'
    compile_cmd = [
        'g++', '-std=c++17', '-O2', '-pthread', f'-I{BUILD}', f'-I{LIBDIR}',
        str(server), str(BUILD / 'calc.pb.cc'), str(BUILD / 'calc.grpc.pb.cc'),
        str(wrapper), str(archive), '-Wl,--wrap=fast_sigmoid_array', '-lm',
        *pkg, '-o', str(binary),
    ]
    run(compile_cmd)
    symbols = run(['nm', '-C', str(binary)]).stdout
    assert re.search(r'\bfast_sigmoid_array\b', symbols), 'The compiled C++ server does not link fast_sigmoid_array from libfastcalc.a'

    stop_port_50051()
    MARKER.unlink(missing_ok=True)
    SERVER_PROCESS = subprocess.Popen(
        [str(binary)], cwd=SERVICE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        grpc.channel_ready_future(grpc.insecure_channel('localhost:50051')).result(timeout=10)
    except Exception:
        code = SERVER_PROCESS.poll()
        pytest.fail(f'Compiled C++ server did not become ready on port 50051 (exit status {code})')
    assert SERVER_PROCESS.poll() is None, 'Compiled C++ server exited unexpectedly'

    sys.path.insert(0, str(BUILD))
    import calc_pb2
    import calc_pb2_grpc

    service_desc = calc_pb2.DESCRIPTOR.services_by_name.get('FastCalc')
    assert service_desc is not None, 'calc.proto must define service FastCalc'
    assert 'GetVersion' in service_desc.methods_by_name, 'FastCalc is missing GetVersion'
    assert 'ComputeSigmoid' in service_desc.methods_by_name, 'FastCalc is missing ComputeSigmoid'
    assert hasattr(calc_pb2_grpc, 'FastCalcStub'), 'Generated module has no FastCalcStub'

    yield calc_pb2, calc_pb2_grpc, service_desc


def test_grpc_server_metrics(built_service):
    calc_pb2, calc_pb2_grpc, service_desc = built_service
    channel = grpc.insecure_channel('localhost:50051')
    stub = calc_pb2_grpc.FastCalcStub(channel)

    version_method = service_desc.methods_by_name['GetVersion']
    version_request = generated_message_class(calc_pb2, version_method.input_type)()
    try:
        version_response = stub.GetVersion(version_request, timeout=5)
    except Exception as exc:
        pytest.fail(f'GetVersion RPC failed: {exc}')

    # Preserve the original substring assertion, then strengthen it to exact field equality.
    assert '1.2.3' in str(version_response), f'Semantic version 1.2.3 not found in response: {version_response}'
    string_fields = [f for f in version_response.DESCRIPTOR.fields if f.type == f.TYPE_STRING and not f.is_repeated]
    assert string_fields, 'GetVersion response has no string field'
    assert any(getattr(version_response, f.name) == '1.2.3' for f in string_fields), 'GetVersion must return exactly "1.2.3"'

    sigmoid_method = service_desc.methods_by_name['ComputeSigmoid']
    request_cls = generated_message_class(calc_pb2, sigmoid_method.input_type)
    input_fields = [f for f in request_cls.DESCRIPTOR.fields if f.is_repeated and f.type == f.TYPE_DOUBLE]
    assert input_fields, 'ComputeSigmoid request has no repeated double field'
    input_field = input_fields[0]

    rng = np.random.default_rng(20260911)
    datasets = [
        np.linspace(-10.0, 10.0, 10000, dtype=np.float64),
        rng.uniform(-10.0, 10.0, 137).astype(np.float64),
        rng.uniform(-10.0, 10.0, 7919).astype(np.float64),
        np.array([-10.0, -7.25, -1.0, -1e-9, 0.0, 1e-9, 1.0, 7.25, 10.0]),
    ]

    MARKER.unlink(missing_ok=True)
    for inputs in datasets:
        request = request_cls(**{input_field.name: inputs.tolist()})
        try:
            response = stub.ComputeSigmoid(request, timeout=10)
        except Exception as exc:
            pytest.fail(f'ComputeSigmoid RPC failed: {exc}')
        output_fields = [f for f in response.DESCRIPTOR.fields if f.is_repeated and f.type == f.TYPE_DOUBLE]
        assert output_fields, 'Response message has no repeated double field'
        outputs = np.asarray(getattr(response, output_fields[0].name), dtype=np.float64)
        expected = expit(inputs)
        assert len(outputs) == len(expected), f'Output length mismatch: {len(outputs)} vs {len(expected)}'
        mse = float(np.mean((outputs - expected) ** 2))
        # Preserve the original threshold assertion and enforce the instruction's strict inequality.
        assert mse <= 1e-4, f'MSE {mse} is greater than threshold 1e-4'
        assert mse < 1e-4, f'MSE {mse} is not less than threshold 1e-4'

    assert MARKER.exists() and MARKER.stat().st_size > 0, 'ComputeSigmoid did not call the linked C fast_sigmoid_array function'


def test_submitted_python_client(built_service):
    # Execute the requested fixture against the freshly compiled C++ server, using modules generated from calc.proto.
    copied_client = BUILD / 'submitted_test_client.py'
    shutil.copy2(SERVICE / 'test_client.py', copied_client)
    env = os.environ.copy()
    env['PYTHONPATH'] = str(BUILD) + os.pathsep + env.get('PYTHONPATH', '')
    result = subprocess.run(
        [sys.executable, str(copied_client)], cwd=BUILD, env=env,
        text=True, capture_output=True, timeout=30,
    )
    assert result.returncode == 0, (
        f'test_client.py failed against the compiled server\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
