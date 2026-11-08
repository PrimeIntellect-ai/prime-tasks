#!/bin/bash
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import socket
import stat
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

HOME = Path('/home/user')
ARTIFACT = HOME / 'artifact.json'
HARNESS = HOME / 'ws_harness.py'
RECEIPT = Path('/tmp') / ('ws_receipt_' + uuid.uuid4().hex + '.json')
SUCCESS = 'E2E_SUCCESS: Valid payload and exit code received.'


def stop_servers():
    subprocess.run(['pkill', '-f', '/home/user/ws_harness.py'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)


def write_harness(expected_id, expected_code):
    source = f'''import asyncio
import json
import websockets

EXPECTED_ID = {expected_id!r}
EXPECTED_CODE = {expected_code!r}
RECEIPT = {str(RECEIPT)!r}

async def handler(websocket, *args):
    message = await websocket.recv()
    data = json.loads(message)
    with open(RECEIPT, "w") as f:
        json.dump(data, f)
    valid = (data.get("artifact_id") == EXPECTED_ID and
             type(data.get("exit_code")) is int and
             data.get("exit_code") == EXPECTED_CODE and
             set(data) == {{"artifact_id", "exit_code"}})
    with open("/home/user/verification.log", "w") as f:
        if valid:
            f.write({SUCCESS!r} + "\\n")
        else:
            f.write("E2E_FAILURE: Invalid data " + repr(data) + "\\n")
    await websocket.send(json.dumps({{"status": "verified" if valid else "rejected"}}))

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
'''
    HARNESS.write_text(source)
    HARNESS.chmod(HARNESS.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def port_is_open():
    try:
        with socket.create_connection(('localhost', 8765), timeout=0.2):
            return True
    except OSError:
        return False


def expected_text_bytes(instructions):
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        src = td / 'expected.s'
        obj = td / 'expected.o'
        elf = td / 'expected'
        raw = td / 'text.bin'
        src.write_text('.intel_syntax noprefix\n.global _start\n.text\n_start:\n' +
                       '\n'.join(instructions) + '\n')
        subprocess.run(['/usr/bin/as', '-o', str(obj), str(src)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(['/usr/bin/ld', '-static', '-o', str(elf), str(obj)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(['/usr/bin/objcopy', '-O', 'binary', '-j', '.text', str(elf), str(raw)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return raw.read_bytes()


def validate_generated(instructions, expected_code):
    payload_s = HOME / 'payload.s'
    payload_bin = HOME / 'payload_bin'

    assert payload_s.exists(), f'Assembly file {payload_s} does not exist.'
    source = payload_s.read_text()
    assert '_start' in source, f'The assembly file {payload_s} is missing the _start symbol.'

    # Every JSON instruction must occur verbatim and in order in the generated source.
    source_lines = [line.strip() for line in source.splitlines()]
    position = -1
    for instruction in instructions:
        try:
            position = source_lines.index(instruction, position + 1)
        except ValueError:
            raise AssertionError(f'payload.s does not contain JSON instruction {instruction!r} in order')

    assert payload_bin.exists(), f'Executable {payload_bin} does not exist. The Makefile may not have built it correctly.'
    assert os.access(payload_bin, os.X_OK), f'File {payload_bin} is not executable.'

    file_output = subprocess.check_output(['file', str(payload_bin)], text=True)
    assert 'ELF 64-bit' in file_output and 'x86-64' in file_output, file_output

    header = subprocess.check_output(['/usr/bin/readelf', '-hW', str(payload_bin)], text=True)
    assert re.search(r'Type:\s+EXEC', header), 'payload_bin is not an ELF executable'
    assert 'Advanced Micro Devices X86-64' in header, 'payload_bin has the wrong architecture'

    program_headers = subprocess.check_output(['/usr/bin/readelf', '-lW', str(payload_bin)], text=True)
    assert 'INTERP' not in program_headers, 'payload_bin contains a dynamic interpreter'
    dynamic = subprocess.run(['/usr/bin/readelf', '-dW', str(payload_bin)], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    assert 'NEEDED' not in dynamic, 'payload_bin has dynamic library dependencies'

    symbols = subprocess.check_output(['/usr/bin/nm', str(payload_bin)], text=True)
    match = re.search(r'^([0-9a-fA-F]+)\s+\w\s+_start$', symbols, re.MULTILINE)
    assert match, 'payload_bin does not export an _start symbol'
    entry_match = re.search(r'Entry point address:\s+0x([0-9a-fA-F]+)', header)
    assert entry_match and int(entry_match.group(1), 16) == int(match.group(1), 16), \
        'ELF entry point is not _start'

    with tempfile.TemporaryDirectory() as td:
        actual = Path(td) / 'text.bin'
        subprocess.run(['/usr/bin/objcopy', '-O', 'binary', '-j', '.text', str(payload_bin), str(actual)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert actual.read_bytes() == expected_text_bytes(instructions), \
            'payload_bin .text does not exactly implement the JSON instruction sequence'

    result = subprocess.run([str(payload_bin)], cwd=HOME)
    assert result.returncode == expected_code, \
        f'payload_bin returned {result.returncode}, expected {expected_code}'


def run_case(artifact):
    artifact_id = artifact['artifact_info']['artifact_id']
    instructions = artifact['payload']['instructions']
    expected_code = int(instructions[-2].split(',', 1)[1].strip())

    ARTIFACT.write_text(json.dumps(artifact, indent=2) + '\n')
    write_harness(artifact_id, expected_code)
    for path in (HOME / 'payload.s', HOME / 'payload_bin', HOME / 'verification.log', RECEIPT):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

    stop_servers()
    result = subprocess.run(['timeout', '35', 'bash', str(HOME / 'run_e2e.sh')], cwd=HOME,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0, 'run_e2e.sh failed:\n' + result.stdout

    deadline = time.time() + 2
    while port_is_open() and time.time() < deadline:
        time.sleep(0.1)
    assert not port_is_open(), 'run_e2e.sh did not terminate the WebSocket server'

    assert RECEIPT.exists(), 'The verifier-controlled WebSocket server received no message'
    received = json.loads(RECEIPT.read_text())
    assert received == {'artifact_id': artifact_id, 'exit_code': expected_code}, \
        f'Incorrect WebSocket payload: {received!r}'

    validate_generated(instructions, expected_code)


def test_complete_workflow():
    original_artifact_bytes = ARTIFACT.read_bytes()
    original_harness_bytes = HARNESS.read_bytes()
    original_harness_mode = HARNESS.stat().st_mode
    try:
        original = json.loads(original_artifact_bytes)
        run_case(original)

        # Preserve the original verifier's assertions.
        log_path = HOME / 'verification.log'
        assert log_path.exists(), f'File {log_path} does not exist. The end-to-end script likely failed or was not run.'
        assert log_path.read_text().strip() == SUCCESS, 'Verification log content is incorrect.'
        assert (HOME / 'Makefile').exists(), f'Makefile at {HOME / "Makefile"} does not exist.'
        assert (HOME / 'run_e2e.sh').exists(), f'Script {HOME / "run_e2e.sh"} does not exist.'
        assert os.access(HOME / 'run_e2e.sh', os.X_OK), f'Script {HOME / "run_e2e.sh"} is not executable.'
        assert (HOME / 'notify.py').exists(), f'Script {HOME / "notify.py"} does not exist.'

        make_text = (HOME / 'Makefile').read_text()
        assert 'payload.s' in make_text and 'payload_bin' in make_text, \
            'Makefile does not define the required payload build'
        assert re.search(r'(^|[^A-Za-z])(as|\$\(AS\))([^A-Za-z]|$)', make_text, re.I), \
            'Makefile does not use GNU as'
        assert re.search(r'(^|[^A-Za-z])(ld|\$\(LD\))([^A-Za-z]|$)', make_text, re.I), \
            'Makefile does not use GNU ld'

        parser_candidates = []
        for script in HOME.glob('*.py'):
            if script.name in ('notify.py', 'ws_harness.py'):
                continue
            text = script.read_text(errors='replace')
            if 'artifact.json' in text and 'payload.s' in text and re.search(r'\bjson\b', text):
                parser_candidates.append(script)
        assert parser_candidates, 'No Python JSON-to-assembly parsing script was found'

        # A second derived case rejects hard-coded IDs, exit codes, assembly, or notification data.
        code = random.SystemRandom().choice([n for n in range(21, 231) if n != 187])
        changed = {
            'schema_version': '1.2',
            'artifact_info': {
                'arch': 'x86_64',
                'artifact_id': 'VERIFY-' + uuid.uuid4().hex,
                'timestamp': 1698765432
            },
            'payload': {
                'instructions': ['mov rax, 60', f'mov rdi, {code}', 'syscall']
            }
        }
        run_case(changed)

        assert (HOME / 'verification.log').read_text().strip() == SUCCESS
    finally:
        stop_servers()
        ARTIFACT.write_bytes(original_artifact_bytes)
        HARNESS.write_bytes(original_harness_bytes)
        HARNESS.chmod(original_harness_mode)
        try:
            RECEIPT.unlink()
        except FileNotFoundError:
            pass
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
