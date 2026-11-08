#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

WORK = '/home/user/build_telemetry'
OUTPUT = os.path.join(WORK, 'telemetry_success.json')
EXPECTED = {
    'apk_size': 15400230,
    'dex_count': 3,
    'lint_errors': 12,
}

HARNESS = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cmap.h"

#define COUNT 32

int main(int argc, char **argv) {
    if (argc != 2) return 2;

    CMap *map = cmap_create(7);
    if (!map || !map->buckets || map->capacity <= 0) return 3;

    char expected[COUNT][160];
    for (int i = 0; i < COUNT; i++) {
        snprintf(expected[i], sizeof(expected[i]), "%s-key-%d-with-variable-length-%d",
                 argv[1], i, i * 17);
        size_t n = strlen(expected[i]);
        char *mutable_key = malloc(n + 1);
        if (!mutable_key) return 4;
        memcpy(mutable_key, expected[i], n + 1);
        cmap_insert(map, mutable_key, 1000 + i * 37);

        /* The map must own an independent copy of each inserted string. */
        memset(mutable_key, 'X', n);
        mutable_key[n] = '\0';
        free(mutable_key);
    }

    int seen[COUNT] = {0};
    for (int bucket = 0; bucket < map->capacity; bucket++) {
        for (CMapNode *node = map->buckets[bucket]; node; node = node->next) {
            int matched = 0;
            for (int i = 0; i < COUNT; i++) {
                if (strcmp(node->key, expected[i]) == 0) {
                    if (node->value != 1000 + i * 37 || seen[i]) return 5;
                    seen[i] = 1;
                    matched = 1;
                    break;
                }
            }
            if (!matched) return 6;
        }
    }

    for (int i = 0; i < COUNT; i++) {
        if (!seen[i]) return 7;
    }

    cmap_free(map);
    return 0;
}
'''


def run_checked(command, **kwargs):
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}"
    )
    return result


def stop_existing_servers():
    own_pid = os.getpid()
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == own_pid:
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                command = f.read().replace(b'\0', b' ')
            if b'server.py' in command:
                os.kill(int(name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


@pytest.fixture(scope='session', autouse=True)
def exercise_submission():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    # A clean build must recreate a native executable through the repaired Makefile.
    run_checked(['make', 'clean'], cwd=WORK)
    run_checked(['make'], cwd=WORK)

    executable = os.path.join(WORK, 'build_reporter')
    assert os.path.isfile(executable), 'make did not produce build_reporter'
    assert os.access(executable, os.X_OK), 'build_reporter is not executable'
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'build_reporter is not a compiled ELF executable'

    # Exercise cmap.c with unpredictable mutable keys and ASan so insertion must
    # allocate and retain independent string storage rather than special-case the metrics.
    harness_source = '/tmp/cmap_verifier.c'
    harness_binary = '/tmp/cmap_verifier'
    with open(harness_source, 'w') as f:
        f.write(HARNESS)
    run_checked([
        'gcc', '-Wall', '-g', '-fsanitize=address', '-fno-omit-frame-pointer',
        '-I', WORK, harness_source, os.path.join(WORK, 'cmap.c'), '-o', harness_binary,
    ])
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
    run_checked([harness_binary, secrets.token_hex(16)], env=env)

    # Replace any agent-started server with a verifier-controlled endpoint, then
    # require the freshly built artifact itself to make the requested HTTP POST.
    stop_existing_servers()
    captured = {}
    received = threading.Event()

    class CaptureHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length)
            captured['path'] = self.path
            captured['content_type'] = self.headers.get('Content-Type', '')
            captured['raw'] = raw
            try:
                data = json.loads(raw.decode('utf-8'))
                captured['data'] = data
                with open(OUTPUT, 'w') as f:
                    json.dump(data, f)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'Success')
            except Exception:
                self.send_response(400)
                self.end_headers()
            finally:
                received.set()

        def log_message(self, *_args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(('127.0.0.1', 8080), CaptureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run(
            [executable], cwd=WORK, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=20,
        )
        assert result.returncode == 0, f'build_reporter failed:\n{result.stdout}'
        assert received.wait(5), 'build_reporter did not POST to the telemetry API'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert captured.get('path') == '/report', 'POST was not sent to /report'
    assert captured.get('content_type', '').split(';', 1)[0].strip().lower() == 'application/json'
    assert captured.get('data') == EXPECTED, f"Unexpected POST payload: {captured.get('data')!r}"


def test_telemetry_success_file_exists():
    assert os.path.isfile(OUTPUT), (
        f'The file {OUTPUT} does not exist. Did the C program run successfully '
        'and send the POST request?'
    )


def test_telemetry_success_content():
    assert os.path.isfile(OUTPUT), f'The file {OUTPUT} does not exist.'
    with open(OUTPUT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {OUTPUT} does not contain valid JSON.')

    for key, expected_value in EXPECTED.items():
        assert key in data, f"Missing key '{key}' in the telemetry JSON output."
        assert data[key] == expected_value, (
            f"Expected '{key}' to be {expected_value}, but got {data[key]}."
        )
    assert len(data) == len(EXPECTED), (
        f'Expected exactly {len(EXPECTED)} keys in the JSON output, but found {len(data)}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
