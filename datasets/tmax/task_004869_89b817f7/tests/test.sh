#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time

import pytest

BASE = '/home/user/network_tools'
ANALYZER = BASE + '/analyzer.py'
LOG = BASE + '/analysis.log'
RECEIPT = BASE + '/receipt.txt'
CERT = BASE + '/server.crt'
KEY = BASE + '/server.key'
RECEIVER = BASE + '/secure_receiver.py'
SENDER = BASE + '/secure_sender.py'


def test_analyzer_modified():
    analyzer_path = '/home/user/network_tools/analyzer.py'
    assert os.path.isfile(analyzer_path), f"File {analyzer_path} does not exist."
    with open(analyzer_path, 'r') as f:
        content = f.read()

    assert "--secret-token" not in content, f"--secret-token argument is still present in {analyzer_path}."
    assert "ANALYZER_TOKEN" in content or "os.environ" in content, f"Environment variable reading logic not found in {analyzer_path}."


def test_analysis_log_exists_and_content():
    log_path = '/home/user/network_tools/analysis.log'
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read()

    expected_content = "TOKEN:SECURE_TOKEN_8842\nDATA_LENGTH:34\n"
    assert content == expected_content, f"Content of {log_path} is incorrect. Expected {repr(expected_content)}, got {repr(content)}."


def test_tls_certs_exist():
    crt_path = '/home/user/network_tools/server.crt'
    key_path = '/home/user/network_tools/server.key'

    assert os.path.isfile(crt_path), f"Certificate file {crt_path} does not exist."
    assert os.path.isfile(key_path), f"Private key file {key_path} does not exist."


def test_transmission_scripts_exist():
    receiver_path = '/home/user/network_tools/secure_receiver.py'
    sender_path = '/home/user/network_tools/secure_sender.py'

    assert os.path.isfile(receiver_path), f"Receiver script {receiver_path} does not exist."
    assert os.path.isfile(sender_path), f"Sender script {sender_path} does not exist."


def test_receipt_txt_content():
    receipt_path = '/home/user/network_tools/receipt.txt'
    assert os.path.isfile(receipt_path), f"File {receipt_path} does not exist."

    expected_log_content = "TOKEN:SECURE_TOKEN_8842\nDATA_LENGTH:34\n"
    expected_hash = hashlib.sha256(expected_log_content.encode('utf-8')).hexdigest()

    with open(receipt_path, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Content of {receipt_path} does not match the expected SHA256 digest."


def run_ok(cmd, **kwargs):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=15, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def wait_for_listener(proc, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert proc.poll() is None, 'Receiver exited before listening on port 8443'
        try:
            with open('/proc/net/tcp', 'r') as f:
                for line in f:
                    fields = line.split()
                    if len(fields) > 3 and fields[1].upper().endswith(':20FB') and fields[3] == '0A':
                        return
        except OSError:
            pass
        time.sleep(0.05)
    pytest.fail('Receiver did not listen on 127.0.0.1:8443')


def terminate(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def test_original_integrity_metadata_is_valid_and_preserved():
    original = b"""import argparse
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--secret-token', required=True)
    parser.add_argument('--data', required=True)
    args = parser.parse_args()

    with open(args.data, 'r') as f:
        content = f.read()

    with open('/home/user/network_tools/analysis.log', 'w') as f:
        f.write(f\"TOKEN:{args.secret_token}\\n\")
        f.write(f\"DATA_LENGTH:{len(content)}\\n\")

if __name__ == '__main__':
    main()
"""
    checksum_path = BASE + '/checksum.txt'
    assert os.path.isfile(checksum_path)
    with open(checksum_path, 'r', encoding='ascii') as f:
        supplied = f.read().strip()
    assert supplied == hashlib.sha384(original).hexdigest(), (
        'checksum.txt no longer contains the SHA384 checksum of the existing legacy analyzer'
    )
    with open(ANALYZER, 'rb') as f:
        assert hashlib.sha384(f.read()).hexdigest() != supplied, 'analyzer.py was not modified'


def test_analyzer_is_executed_and_uses_only_environment_token():
    token = 'DYNAMIC_' + secrets.token_hex(18)
    payload = ('pcap-' + secrets.token_hex(29))
    fd, data_path = tempfile.mkstemp(prefix='verifier-pcap-', dir='/tmp')
    try:
        os.write(fd, payload.encode('utf-8'))
    finally:
        os.close(fd)

    try:
        env = os.environ.copy()
        env.pop('ANALYZER_TOKEN', None)
        missing = subprocess.run(
            ['python3', ANALYZER, '--data', data_path], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert missing.returncode != 0, 'Analyzer accepted a missing ANALYZER_TOKEN'

        env['ANALYZER_TOKEN'] = token
        old_cli = subprocess.run(
            ['python3', ANALYZER, '--data', data_path, '--secret-token', 'LEAKED'],
            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert old_cli.returncode != 0, 'Analyzer still accepts --secret-token'

        run_ok(['python3', ANALYZER, '--data', data_path], env=env)
        with open(LOG, 'r') as f:
            actual = f.read()
        assert actual == f'TOKEN:{token}\nDATA_LENGTH:{len(payload)}\n'
    finally:
        os.unlink(data_path)


def test_certificate_and_key_are_valid_rsa2048_for_localhost():
    cert_text = run_ok(['openssl', 'x509', '-in', CERT, '-noout', '-text']).stdout
    assert 'Public Key Algorithm: rsaEncryption' in cert_text
    assert 'Public-Key: (2048 bit)' in cert_text
    run_ok(['openssl', 'x509', '-in', CERT, '-noout', '-checkend', '0'])
    run_ok(['openssl', 'pkey', '-in', KEY, '-noout', '-check'])
    run_ok(['openssl', 'verify', '-CAfile', CERT, '-verify_hostname', 'localhost', CERT])

    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', CERT, '-pubkey', '-noout'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    key_pub = subprocess.run(
        ['openssl', 'pkey', '-in', KEY, '-pubout'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    assert cert_pub == key_pub, 'server.crt and server.key do not form a matching pair'

    names = run_ok([
        'openssl', 'x509', '-in', CERT, '-noout', '-subject', '-issuer',
        '-nameopt', 'RFC2253'
    ]).stdout.splitlines()
    assert len(names) == 2
    assert names[0].removeprefix('subject=') == names[1].removeprefix('issuer='), (
        'Certificate is not self-signed'
    )


def test_receiver_is_a_real_tls_server_and_hashes_dynamic_data():
    data = ('receiver-' + secrets.token_hex(80)).encode('ascii')
    try:
        os.unlink(RECEIPT)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(['python3', RECEIVER], stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True)
    try:
        wait_for_listener(proc)
        context = ssl._create_unverified_context()
        with socket.create_connection(('127.0.0.1', 8443), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname='localhost') as tls:
                tls.sendall(data)
        _, stderr = proc.communicate(timeout=8)
        assert proc.returncode == 0, f'Receiver failed: {stderr}'
    finally:
        terminate(proc)

    with open(RECEIPT, 'r') as f:
        receipt = f.read()
    assert receipt == hashlib.sha256(data).hexdigest()


def test_sender_is_a_real_tls_client_and_sends_entire_log():
    data = ('sender-' + secrets.token_hex(90) + '\n').encode('ascii')
    with open(LOG, 'wb') as f:
        f.write(data)

    ready = threading.Event()
    result = {'data': b'', 'error': None}

    def tls_server():
        try:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(CERT, KEY)
            with socket.socket() as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(('127.0.0.1', 8443))
                listener.listen(1)
                ready.set()
                conn, _ = listener.accept()
                with conn:
                    with context.wrap_socket(conn, server_side=True) as tls:
                        chunks = []
                        while True:
                            chunk = tls.recv(4096)
                            if not chunk:
                                break
                            chunks.append(chunk)
                        result['data'] = b''.join(chunks)
        except BaseException as exc:
            result['error'] = exc
            ready.set()

    thread = threading.Thread(target=tls_server, daemon=True)
    thread.start()
    assert ready.wait(5), 'Verifier TLS server did not start'
    assert result['error'] is None
    sent = subprocess.run(['python3', SENDER], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=10)
    thread.join(8)
    assert not thread.is_alive(), 'Sender did not close its TLS connection'
    assert sent.returncode == 0, f'Sender failed: {sent.stderr}'
    assert result['error'] is None, f'TLS server failed: {result["error"]}'
    assert result['data'] == data


def test_sender_and_receiver_execute_together_and_produce_dynamic_receipt():
    data = ('integration-' + secrets.token_hex(100) + '\n').encode('ascii')
    with open(LOG, 'wb') as f:
        f.write(data)
    try:
        os.unlink(RECEIPT)
    except FileNotFoundError:
        pass

    receiver = subprocess.Popen(['python3', RECEIVER], stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, text=True)
    try:
        wait_for_listener(receiver)
        sender = subprocess.run(['python3', SENDER], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, timeout=10)
        assert sender.returncode == 0, f'Sender failed: {sender.stderr}'
        _, receiver_stderr = receiver.communicate(timeout=8)
        assert receiver.returncode == 0, f'Receiver failed: {receiver_stderr}'
    finally:
        terminate(receiver)

    with open(RECEIPT, 'r') as f:
        receipt = f.read()
    assert receipt == hashlib.sha256(data).hexdigest()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
