#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SERVER_EOF' > /tmp/counting_smtp_server.py
import base64
import json
import signal
import sys
import threading

sys.path.insert(0, '/app/aiosmtpd')
from aiosmtpd.controller import Controller

messages = []
stopping = threading.Event()

class CountingHandler:
    async def handle_DATA(self, server, session, envelope):
        messages.append({
            'mail_from': envelope.mail_from,
            'rcpt_tos': list(envelope.rcpt_tos),
            'content': base64.b64encode(envelope.content).decode('ascii'),
        })
        return '250 Message accepted for delivery'

def stop_handler(signum, frame):
    stopping.set()

signal.signal(signal.SIGTERM, stop_handler)
signal.signal(signal.SIGINT, stop_handler)

controller = Controller(CountingHandler(), hostname='127.0.0.1', port=8025)
controller.start()
try:
    stopping.wait()
finally:
    controller.stop()
    print(json.dumps(messages), flush=True)
SERVER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import signal
import socket
import subprocess
import time
from email import policy
from email.parser import BytesParser


def wait_for_port(port, timeout=5.0):
    start = time.time()
    while time.time() - start < timeout:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(('127.0.0.1', port)) == 0:
                return True
        time.sleep(0.1)
    return False


def kill_existing_server(port):
    try:
        output = subprocess.check_output(['lsof', '-t', f'-i:{port}']).decode().strip()
        if output:
            for pid in output.split('\n'):
                os.kill(int(pid), signal.SIGKILL)
            time.sleep(0.5)
    except Exception:
        subprocess.run(
            ['pkill', '-9', '-f', '/app/run_server.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        subprocess.run(
            ['pkill', '-9', '-f', '/tmp/counting_smtp_server.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        time.sleep(0.5)


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2.0)


def assert_output_and_original_metrics(res, actual_duration):
    assert res.returncode == 0, (
        f'Stress test script failed with return code {res.returncode}. '
        f'Stderr: {res.stderr}'
    )

    match = re.search(
        r'Total time:\s*([0-9.]+)\s*seconds',
        res.stdout,
        re.IGNORECASE,
    )
    assert match is not None, (
        "Could not find 'Total time: X.XXX seconds' in output. "
        f'Output was: {res.stdout}'
    )

    reported_time = float(match.group(1))
    assert reported_time < 2.0, (
        f'Reported time {reported_time} is not < 2.0 seconds. '
        'The bug may not be fixed.'
    )
    assert actual_duration < 5.0, (
        f'Actual execution time {actual_duration:.2f}s is too high. '
        'The bug may not be fixed.'
    )

    assert re.fullmatch(
        r'Total time: [0-9]+\.[0-9]{3} seconds\n?', res.stdout
    ), f'Output was not in the exact required format: {res.stdout!r}'


def test_stress_test_script_exists():
    assert os.path.isfile('/home/user/stress_test.py'), (
        '/home/user/stress_test.py script is missing.'
    )


def test_performance_and_output():
    script_path = '/home/user/stress_test.py'
    assert os.path.isfile(script_path), f'{script_path} does not exist'

    kill_existing_server(8025)

    server_proc = subprocess.Popen(
        ['python3', '/app/run_server.py'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        assert wait_for_port(8025, timeout=5.0), (
            'Server did not start on port 8025'
        )

        start_time = time.time()
        res = subprocess.run(
            ['python3', script_path],
            capture_output=True,
            text=True,
        )
        actual_duration = time.time() - start_time
        assert_output_and_original_metrics(res, actual_duration)
    finally:
        stop_process(server_proc)

    kill_existing_server(8025)

    counting_proc = subprocess.Popen(
        ['python3', '/tmp/counting_smtp_server.py'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        assert wait_for_port(8025, timeout=5.0), (
            'Verifier SMTP server did not start on port 8025'
        )

        start_time = time.time()
        verified_res = subprocess.run(
            ['python3', script_path],
            capture_output=True,
            text=True,
        )
        verified_duration = time.time() - start_time
        assert_output_and_original_metrics(verified_res, verified_duration)
        assert verified_duration < 2.0, (
            f'Sending the messages actually took {verified_duration:.3f} seconds, '
            'which is not under 2.0 seconds.'
        )
    finally:
        if counting_proc.poll() is None:
            counting_proc.terminate()
        try:
            server_stdout, server_stderr = counting_proc.communicate(timeout=3.0)
        except subprocess.TimeoutExpired:
            counting_proc.kill()
            server_stdout, server_stderr = counting_proc.communicate(timeout=2.0)

    assert counting_proc.returncode == 0, (
        f'Verifier SMTP server failed: {server_stderr}'
    )
    try:
        messages = json.loads(server_stdout.strip())
    except Exception as exc:
        raise AssertionError(
            f'Could not read verifier SMTP delivery records: {server_stdout!r}; '
            f'stderr={server_stderr!r}'
        ) from exc

    assert len(messages) == 50, (
        f'Expected exactly 50 delivered messages, received {len(messages)}.'
    )

    for index, record in enumerate(messages, 1):
        assert record['mail_from'] == 'test@example.com', (
            f'Message {index} had incorrect envelope sender: '
            f"{record['mail_from']!r}"
        )
        assert record['rcpt_tos'] == ['dest@example.com'], (
            f'Message {index} had incorrect envelope recipients: '
            f"{record['rcpt_tos']!r}"
        )

        raw_message = base64.b64decode(record['content'])
        parsed = BytesParser(policy=policy.default).parsebytes(raw_message)
        assert parsed['Subject'] == 'Test', (
            f'Message {index} had incorrect Subject: {parsed["Subject"]!r}'
        )
        body = parsed.get_body(preferencelist=('plain',))
        body_text = body.get_content() if body is not None else parsed.get_payload()
        assert body_text.strip() == 'This is a test', (
            f'Message {index} had incorrect body: {body_text!r}'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
