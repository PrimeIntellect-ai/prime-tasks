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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import socket
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path

import dpkt
import pytest
import requests

ROOT = Path('/app/vendor/pcap-processor')
PROCESSOR = ROOT / 'processor.py'
SERVER = ROOT / 'server.py'
PROVIDED_PCAP = Path('/app/data/test.pcap')


def sequential_counts(path):
    counts = {'tcp_count': 0, 'udp_count': 0}
    with open(path, 'rb') as f:
        for _, buf in dpkt.pcap.Reader(f):
            eth = dpkt.ethernet.Ethernet(buf)
            if not isinstance(eth.data, dpkt.ip.IP):
                continue
            if isinstance(eth.data.data, dpkt.tcp.TCP):
                counts['tcp_count'] += 1
            elif isinstance(eth.data.data, dpkt.udp.UDP):
                counts['udp_count'] += 1
    return counts


def write_pcap(path, tcp_count, udp_count):
    kinds = ['tcp'] * tcp_count + ['udp'] * udp_count
    random.SystemRandom().shuffle(kinds)
    with open(path, 'wb') as f:
        writer = dpkt.pcap.Writer(f)
        for i, kind in enumerate(kinds):
            if kind == 'tcp':
                transport = dpkt.tcp.TCP(sport=10000 + (i % 1000), dport=80)
                proto = dpkt.ip.IP_PROTO_TCP
            else:
                transport = dpkt.udp.UDP(sport=20000 + (i % 1000), dport=53)
                transport.ulen = len(transport)
                proto = dpkt.ip.IP_PROTO_UDP
            ip = dpkt.ip.IP(src=b'\x0a\x00\x00\x01', dst=b'\x0a\x00\x00\x02', p=proto, data=transport)
            ip.len = len(ip)
            eth = dpkt.ethernet.Ethernet(
                src=b'\x00\x11\x22\x33\x44\x55',
                dst=b'\x66\x77\x88\x99\xaa\xbb',
                type=dpkt.ethernet.ETH_TYPE_IP,
                data=ip,
            )
            writer.writepkt(bytes(eth), ts=i / 1000.0)
        writer.close()


def load_processor():
    import importlib.util
    name = 'verified_processor_' + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, PROCESSOR)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tcp_query(query):
    with socket.create_connection(('127.0.0.1', 8081), timeout=3) as s:
        s.sendall((json.dumps({'query': query}) + '\n').encode())
        data = b''
        while not data.endswith(b'\n'):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
    return json.loads(data.decode().strip())


def wait_for_server(expected, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get('http://127.0.0.1:8080/stats', timeout=1)
            if response.status_code == 200 and response.json() == expected:
                if tcp_query('tcp').get('count') == expected['tcp_count'] and tcp_query('udp').get('count') == expected['udp_count']:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f'server did not become ready with expected counts {expected}: {last_error}')


def listener_pids(ports):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == '0A':
                port = int(fields[1].split(':')[1], 16)
                if port in ports:
                    inodes.add(fields[9])
    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def stop_listeners():
    for pid in listener_pids({8080, 8081}):
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline:
        if not listener_pids({8080, 8081}):
            return
        time.sleep(0.1)
    for pid in listener_pids({8080, 8081}):
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def test_makefile_fixed_and_test_suite_really_runs():
    makefile_path = ROOT / 'Makefile'
    assert makefile_path.is_file(), f'File {makefile_path} does not exist'
    content = makefile_path.read_text()
    assert 'PYTHONPATH=/wrong/path' not in content, 'Makefile still contains the wrong PYTHONPATH'

    token = uuid.uuid4().hex
    sentinel = Path('/tmp') / ('make_probe_' + token)
    probe = ROOT / 'tests' / ('test_verifier_probe_' + token + '.py')
    probe.write_text(
        'import unittest\n'
        'from pathlib import Path\n'
        'import processor\n\n'
        'class TestVerifierProbe(unittest.TestCase):\n'
        '    def test_make_executes_discovered_tests(self):\n'
        f"        Path({str(sentinel)!r}).write_text('executed')\n"
    )
    try:
        result = subprocess.run(
            ['make', 'test'], cwd=ROOT, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=60
        )
        assert result.returncode == 0, f'make test failed:\n{result.stdout}'
        assert sentinel.read_text() == 'executed', f'make test did not execute the discovered test suite:\n{result.stdout}'
    finally:
        probe.unlink(missing_ok=True)
        sentinel.unlink(missing_ok=True)


def test_mre_script_exists_and_runs_repeated_analysis():
    mre_path = Path('/home/user/mre.py')
    assert mre_path.is_file(), f'MRE script {mre_path} does not exist'
    source = mre_path.read_text()
    tree = ast.parse(source, filename=str(mre_path))
    assert '/app/data/test.pcap' in source, 'MRE does not process the required pcap file'
    assert any(isinstance(n, (ast.For, ast.While)) for n in ast.walk(tree)), 'MRE does not repeat the analysis'
    assert any(
        isinstance(n, ast.Call) and
        ((isinstance(n.func, ast.Name) and n.func.id == 'run_analysis') or
         (isinstance(n.func, ast.Attribute) and n.func.attr == 'run_analysis'))
        for n in ast.walk(tree)
    ), 'MRE does not call processor.run_analysis'
    assert any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == 'print' for n in ast.walk(tree)), 'MRE does not print its output'

    result = subprocess.run(
        [sys.executable, str(mre_path)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f'MRE failed to execute:\n{result.stderr}'
    expected = sequential_counts(PROVIDED_PCAP)
    matching = 0
    for line in result.stdout.splitlines():
        try:
            value = ast.literal_eval(line.strip())
        except Exception:
            try:
                value = json.loads(line.strip())
            except Exception:
                continue
        if isinstance(value, dict) and value.get('tcp_count') == expected['tcp_count'] and value.get('udp_count') == expected['udp_count']:
            matching += 1
    assert matching >= 2, f'MRE did not repeatedly print correct analysis results; output was:\n{result.stdout}'


def test_processor_handles_derived_counts_under_forced_thread_interleaving(tmp_path):
    tcp_count = random.SystemRandom().randint(421, 731)
    udp_count = random.SystemRandom().randint(233, 419)
    pcap = tmp_path / 'concurrency.pcap'
    write_pcap(pcap, tcp_count, udp_count)
    expected = sequential_counts(pcap)
    assert expected == {'tcp_count': tcp_count, 'udp_count': udp_count}

    processor = load_processor()
    old_interval = sys.getswitchinterval()
    old_trace = threading.gettrace() if hasattr(threading, 'gettrace') else None

    def interleave(frame, event, arg):
        if event == 'line' and frame.f_code.co_filename == str(PROCESSOR) and frame.f_code.co_name == 'process_packet':
            time.sleep(0.00005)
        return interleave

    try:
        sys.setswitchinterval(0.000001)
        threading.settrace(interleave)
        for _ in range(3):
            result = processor.run_analysis(str(pcap))
            assert dict(result) == expected, f'concurrent analysis returned {result}, expected {expected}'
    finally:
        threading.settrace(old_trace)
        sys.setswitchinterval(old_interval)


def test_http_endpoint_stats():
    try:
        response = requests.get('http://127.0.0.1:8080/stats', timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to HTTP server on port 8080: {e}')
    assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON: {response.text}')
    assert data.get('tcp_count') == 10000, f"Expected tcp_count=10000, got {data.get('tcp_count')}"
    assert data.get('udp_count') == 5000, f"Expected udp_count=5000, got {data.get('udp_count')}"


def test_tcp_endpoint_tcp_query():
    try:
        data = tcp_query('tcp')
    except Exception as e:
        pytest.fail(f'Failed to connect or communicate with TCP server on port 8081: {e}')
    assert data.get('count') == 10000, f"Expected count=10000 for tcp query, got {data.get('count')}"


def test_tcp_endpoint_udp_query():
    try:
        data = tcp_query('udp')
    except Exception as e:
        pytest.fail(f'Failed to connect or communicate with TCP server on port 8081: {e}')
    assert data.get('count') == 5000, f"Expected count=5000 for udp query, got {data.get('count')}"


def test_server_uses_processor_results_for_nonfixed_input(tmp_path):
    tcp_count = random.SystemRandom().randint(37, 91)
    udp_count = random.SystemRandom().randint(13, 35)
    dynamic_pcap = tmp_path / ('input_' + uuid.uuid4().hex + '.pcap')
    write_pcap(dynamic_pcap, tcp_count, udp_count)
    expected = sequential_counts(dynamic_pcap)
    assert expected != {'tcp_count': 10000, 'udp_count': 5000}

    dynamic_server = None
    restored_server = None
    stop_listeners()
    try:
        dynamic_server = subprocess.Popen(
            [sys.executable, str(SERVER), str(dynamic_pcap)], cwd=ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        wait_for_server(expected)
        response = requests.get('http://127.0.0.1:8080/stats', timeout=2)
        assert response.status_code == 200
        assert response.json() == expected
        assert tcp_query('tcp').get('count') == expected['tcp_count']
        assert tcp_query('udp').get('count') == expected['udp_count']
    finally:
        if dynamic_server is not None:
            dynamic_server.terminate()
            try:
                dynamic_server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                dynamic_server.kill()
        stop_listeners()
        restored_server = subprocess.Popen(
            [sys.executable, str(SERVER), str(PROVIDED_PCAP)], cwd=ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        wait_for_server({'tcp_count': 10000, 'udp_count': 5000}, timeout=20)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
