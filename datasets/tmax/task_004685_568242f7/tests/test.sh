#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import logging
import logging.handlers
import os
import re
import runpy
import shutil
import socket
import subprocess
import tempfile

SCRIPT = '/home/user/vnc_monitor.py'
LOG_DIR = '/home/user/vnc_logs'
BASE_LOG = '/home/user/vnc_logs/monitor.log'
LOG_PATTERN = re.compile(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3} - VNC_STATUS - (SUCCESS|FAILED)$')


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line for line in f.read().splitlines() if line]


def test_vnc_logs_directory():
    """Verify that the /home/user/vnc_logs directory exists."""
    assert os.path.isdir(LOG_DIR), "Directory /home/user/vnc_logs does not exist."


def test_vnc_monitor_script():
    """Verify that the script exists and retains the required configuration."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."

    with open(SCRIPT, 'r') as f:
        content = f.read()

    assert 'RotatingFileHandler' in content, "RotatingFileHandler not found in the script."
    assert 'maxBytes=60' in content.replace(' ', ''), "maxBytes=60 not found in the script."
    assert 'backupCount=3' in content.replace(' ', ''), "backupCount=3 not found in the script."
    assert '%(asctime)s - VNC_STATUS - %(message)s' in content, "Required log format not found in the script."


def test_log_files_and_rotation():
    """Verify that the submitted final state contains the base log and all backups."""
    assert os.path.isfile(BASE_LOG), f"Base log file {BASE_LOG} does not exist."
    for i in range(1, 4):
        backup = f"{BASE_LOG}.{i}"
        assert os.path.isfile(backup), f"Backup log file {backup} does not exist. Did you run the script 5 times?"


def test_log_contents():
    """Verify that every required log is nonempty and contains only valid records."""
    for log_file in [BASE_LOG] + [f"{BASE_LOG}.{i}" for i in range(1, 4)]:
        assert os.path.isfile(log_file), f"Required log file {log_file} is missing."
        lines = read_nonempty_lines(log_file)
        assert lines, f"Log file {log_file} is empty."
        for line in lines:
            assert LOG_PATTERN.fullmatch(line), (
                f"Log line '{line}' in {log_file} does not match the required format."
            )


def test_five_real_sequential_executions_rotate():
    """Execute the artifact as a standalone script five times against a fresh log directory."""
    parent = os.path.dirname(LOG_DIR)
    saved = tempfile.mkdtemp(prefix='saved_vnc_logs_', dir=parent)
    saved_dir = os.path.join(saved, 'vnc_logs')
    shutil.move(LOG_DIR, saved_dir)
    os.mkdir(LOG_DIR)
    try:
        for run_number in range(1, 6):
            result = subprocess.run(
                ['python3', SCRIPT], text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=8
            )
            assert result.returncode == 0, (
                f"Standalone execution {run_number} failed: {result.stderr}"
            )

        files = [BASE_LOG] + [f"{BASE_LOG}.{i}" for i in range(1, 4)]
        for path in files:
            assert os.path.isfile(path), f"Five executions did not create {path}."
            lines = read_nonempty_lines(path)
            assert lines, f"Five executions left {path} empty."
            for line in lines:
                assert LOG_PATTERN.fullmatch(line), f"Invalid generated record: {line!r}"
    finally:
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        shutil.move(saved_dir, LOG_DIR)
        shutil.rmtree(saved, ignore_errors=True)


def test_socket_logger_and_idempotency_behavior():
    """Instrument the script to verify its socket, logger, handler, and outcome behavior."""
    real_socket = socket.socket
    real_create_connection = socket.create_connection
    real_rfh = logging.handlers.RotatingFileHandler
    real_call_handlers = logging.Logger.callHandlers

    observations = []
    emitted = []
    handlers_created = []
    outcome = {'fail': False}

    class FakeSocket:
        def __init__(self, family=socket.AF_INET, socktype=socket.SOCK_STREAM, *args, **kwargs):
            self.family = family
            self.socktype = socktype
            self.timeout = None
            observations.append(('socket', family, socktype))

        def settimeout(self, timeout):
            self.timeout = timeout
            observations.append(('timeout', timeout))

        def connect(self, address):
            observations.append(('connect', address, self.timeout))
            if outcome['fail']:
                raise ConnectionRefusedError('controlled refusal')

        def connect_ex(self, address):
            observations.append(('connect_ex', address, self.timeout))
            return 111 if outcome['fail'] else 0

        def close(self):
            observations.append(('close',))

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            self.close()

    def fake_create_connection(address, timeout=None, *args, **kwargs):
        observations.append(('create_connection', address, timeout))
        if outcome['fail']:
            raise ConnectionRefusedError('controlled refusal')
        return FakeSocket()

    class TrackingRotatingFileHandler(real_rfh):
        def __init__(self, filename, *args, **kwargs):
            super().__init__(filename, *args, **kwargs)
            handlers_created.append(self)

    def tracking_call_handlers(logger, record):
        if logger.name == 'vnc_logger':
            emitted.append(record.getMessage())
        return real_call_handlers(logger, record)

    logger = logging.getLogger('vnc_logger')
    for handler in list(logger.handlers):
        logger.removeHandler(handler)
        handler.close()
    logger.propagate = False

    socket.socket = FakeSocket
    socket.create_connection = fake_create_connection
    logging.handlers.RotatingFileHandler = TrackingRotatingFileHandler
    logging.Logger.callHandlers = tracking_call_handlers
    try:
        outcome['fail'] = False
        runpy.run_path(SCRIPT, run_name='__main__')
        first_handler_count = len(logger.handlers)
        assert emitted == ['SUCCESS'], f"Successful connection logged {emitted!r}, not exactly SUCCESS."
        assert logger.name == 'vnc_logger'
        assert handlers_created, "The script did not construct a RotatingFileHandler."

        handler = handlers_created[0]
        assert os.path.abspath(handler.baseFilename) == BASE_LOG
        assert handler.maxBytes == 60
        assert handler.backupCount == 3
        assert handler.formatter is not None
        assert handler.formatter._fmt == '%(asctime)s - VNC_STATUS - %(message)s'
        assert first_handler_count >= 1, "The configured logger has no file handler."

        emitted.clear()
        runpy.run_path(SCRIPT, run_name='__main__')
        assert emitted == ['SUCCESS']
        assert len(logger.handlers) == first_handler_count, (
            "Running/importing the script again stacked additional handlers."
        )

        emitted.clear()
        outcome['fail'] = True
        runpy.run_path(SCRIPT, run_name='__main__')
        assert emitted == ['FAILED'], f"Refused connection logged {emitted!r}, not exactly FAILED."

        connection_events = [event for event in observations if event[0] in ('connect', 'connect_ex', 'create_connection')]
        assert connection_events, "The script never attempted a socket connection."
        for event in connection_events:
            assert event[1] == ('127.0.0.1', 5900), f"Wrong connection target: {event[1]!r}"
            if event[0] == 'create_connection':
                assert event[2] == 2, f"Wrong socket timeout: {event[2]!r}"
            else:
                assert event[2] == 2, f"Socket connect occurred without a 2-second timeout: {event!r}"

        socket_events = [event for event in observations if event[0] == 'socket']
        if socket_events:
            for event in socket_events:
                assert event[1] == socket.AF_INET, "The script did not use an IPv4 socket."
                assert event[2] == socket.SOCK_STREAM, "The script did not use a TCP stream socket."
    finally:
        socket.socket = real_socket
        socket.create_connection = real_create_connection
        logging.handlers.RotatingFileHandler = real_rfh
        logging.Logger.callHandlers = real_call_handlers
        for handler in list(logger.handlers):
            logger.removeHandler(handler)
            handler.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
