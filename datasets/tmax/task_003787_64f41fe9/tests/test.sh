#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import socket
import subprocess
from pathlib import Path

LIBDIR = Path('/app/vendored/libcml-0.4.2')
SOURCE = LIBDIR / 'cml.c'
MAKEFILE = LIBDIR / 'Makefile'
SERVER_SOURCE = Path('/home/user/infer_server.c')
SERVER_BINARY = Path('/home/user/infer_server')


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=True, **kwargs)


def function_body(source, name):
    match = re.search(r'\b' + re.escape(name) + r'\s*\([^;]*?\)\s*\{', source, re.S)
    assert match, f'{name} definition not found'
    start = match.end() - 1
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == '{':
            depth += 1
        elif source[pos] == '}':
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise AssertionError(f'unterminated {name} definition')


def request(lines, timeout=2.0):
    with socket.create_connection(('127.0.0.1', 8888), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall((''.join(lines)).encode())
        data = b''
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            data += chunk
        return data.decode(errors='replace')


def predictions(lines):
    text = request(['AUTH: m10ps_t0k3n\n'] + lines + ['QUIT\n'])
    result = []
    for line in text.splitlines():
        match = re.fullmatch(r'RESULT: (-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)', line)
        assert match, f'invalid server response line: {line!r}'
        value = float(match.group(1))
        assert math.isfinite(value)
        assert re.fullmatch(r'-?\d+\.\d{4}', match.group(1)), 'prediction is not formatted as %.4f'
        result.append(value)
    assert len(result) == len(lines), (text, lines)
    return result


def listener_pid():
    inode = None
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            rows = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local, state = fields[1], fields[3]
            if local.endswith(':22B8') and state == '0A':
                # For IPv4, 0100007F is 127.0.0.1. Do not accept 0.0.0.0.
                if table.endswith('tcp') and local.split(':')[0] != '0100007F':
                    continue
                inode = fields[9]
                break
        if inode:
            break
    assert inode, 'nothing is listening on 127.0.0.1:8888'
    needle = f'socket:[{inode}]'
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    if os.readlink(fd) == needle:
                        return int(proc.name)
                except OSError:
                    pass
        except OSError:
            pass
    raise AssertionError('could not find process owning port 8888')


def test_dummy():
    assert True


def test_makefile_supports_optimization_override_and_math_linking():
    assert MAKEFILE.is_file()
    make_text = MAKEFILE.read_text()
    assert '-lm' in make_text, 'Makefile does not link the standard math library'
    run(['make', '-C', str(LIBDIR), 'clean'])
    output = run(['make', '-C', str(LIBDIR), 'CFLAGS=-O3 -fPIC']).stdout
    assert '-O3' in output, 'caller-provided CFLAGS were not used'
    assert (LIBDIR / 'libcml.so').is_file()
    assert (LIBDIR / 'libcml.so').read_bytes()[:4] == b'\x7fELF'


def test_libcml_uses_model_scaling_and_computes_predictions(tmp_path):
    source = SOURCE.read_text()
    body = function_body(source, 'cml_predict_batch')
    assert re.search(r'\bcml_transform_scale\s*\(', body), 'prediction does not use model scaling'
    assert not re.search(r'\bcml_fit_transform_scale\s*\(', body), 'prediction still fits on inference data'

    harness = tmp_path / 'check_cml.c'
    harness.write_text(r'''
#include <math.h>
#include "cml.h"
int main(void) {
    double weights[2] = {2.0, -1.0};
    double means[2] = {1.0, 10.0};
    double stds[2] = {2.0, 5.0};
    cml_model_t model = {2, weights, 0.5, means, stds};
    double batch[4] = {3.0, 20.0, 5.0, 5.0};
    double out[2] = {0.0, 0.0};
    cml_predict_batch(&model, batch, 2, out);
    if (fabs(batch[0]-1.0)>1e-9 || fabs(batch[1]-2.0)>1e-9 ||
        fabs(batch[2]-2.0)>1e-9 || fabs(batch[3]+1.0)>1e-9) return 10;
    if (fabs(out[0]-0.5)>1e-9 || fabs(out[1]-5.5)>1e-9) return 11;
    double single[2] = {3.0, 20.0}, one[1];
    cml_predict_batch(&model, single, 1, one);
    if (fabs(one[0]-out[0])>1e-9) return 12;
    return 0;
}
''')
    exe = tmp_path / 'check_cml'
    run(['gcc', '-O3', '-I' + str(LIBDIR), str(harness), '-L' + str(LIBDIR),
         '-Wl,-rpath,' + str(LIBDIR), '-lcml', '-lm', '-o', str(exe)])
    run([str(exe)])


def test_server_is_compiled_c_artifact_and_uses_one_selected_model(tmp_path):
    assert SERVER_SOURCE.is_file(), 'missing /home/user/infer_server.c'
    assert SERVER_BINARY.is_file(), 'missing compiled /home/user/infer_server'
    assert SERVER_BINARY.read_bytes()[:4] == b'\x7fELF', 'server is not an ELF binary'
    source = SERVER_SOURCE.read_text()
    assert 'cml_predict_batch' in source, 'server does not use fixed libcml inference'
    selected = set(re.findall(r'model_[ABC]\.bin', source))
    assert len(selected) == 1, f'server must identify one selected model, found {selected}'
    assert (Path('/app/models') / next(iter(selected))).is_file()

    rebuilt = tmp_path / 'infer_server'
    run(['gcc', '-O3', '-I' + str(LIBDIR), str(SERVER_SOURCE), '-L' + str(LIBDIR),
         '-Wl,-rpath,' + str(LIBDIR), '-lcml', '-lm', '-o', str(rebuilt)])

    pid = listener_pid()
    running_exe = Path(f'/proc/{pid}/exe').resolve()
    assert os.path.samefile(running_exe, SERVER_BINARY), 'port 8888 is not served by the compiled infer_server'
    linked = run(['ldd', str(SERVER_BINARY)]).stdout
    assert 'libcml' in linked, 'server binary is not linked with libcml'


def test_authentication_is_enforced():
    for payload in (['AUTH: wrong\n'], ['PREDICT: 0.1,0.2,0.3,0.4\n']):
        with socket.create_connection(('127.0.0.1', 8888), timeout=2) as sock:
            sock.settimeout(1)
            sock.sendall(''.join(payload).encode())
            try:
                data = sock.recv(1024)
            except ConnectionResetError:
                data = b''
            except socket.timeout:
                raise AssertionError('unauthenticated connection was not closed immediately')
            assert data == b''


def test_protocol_validation_data_and_batch_reproducibility():
    rows = []
    for line in Path('/app/data/val.csv').read_text().splitlines()[:5]:
        values = [float(x) for x in line.split(',')]
        assert len(values) == 5
        rows.append(values)
    lines = ['PREDICT: ' + ','.join(str(x) for x in row[:4]) + '\n' for row in rows]
    vals = predictions(lines)
    mse = sum((p-row[4])**2 for p, row in zip(vals, rows)) / len(rows)
    assert math.isfinite(mse)

    target = 'PREDICT: 0.25,-1.5,3.75,8.0\n'
    other = 'PREDICT: 1000,-900,0.001,42\n'
    alone = predictions([target])[0]
    mixed = predictions([target, other])[0]
    assert alone == mixed, 'prediction changes based on another item in the request stream'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
