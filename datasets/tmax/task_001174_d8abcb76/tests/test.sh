#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import os
import subprocess
import sys

import pytest

PROJECT = "/home/user/ws_asm"
TEST_FILE = os.path.join(PROJECT, "test_server.py")
CLIENT_FILE = os.path.join(PROJECT, "client.py")
LOG_FILE = os.path.join(PROJECT, "response.log")


def test_pytest_passes():
    """Preserve the original requirement that the submitted test suite passes."""
    assert os.path.isfile(TEST_FILE), f"Test file {TEST_FILE} is missing."
    result = subprocess.run(
        [sys.executable, "-m", "pytest", TEST_FILE],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pytest on {TEST_FILE} failed:\n{result.stdout}\n{result.stderr}"
    )


def test_submitted_fixture_really_runs_a_websocket_server(tmp_path):
    """Exercise ws_server from a trusted test rather than trusting editable tests."""
    trusted_test = tmp_path / "test_fixture_behavior.py"
    trusted_test.write_text(
        "import sys\n"
        f"sys.path.insert(0, {PROJECT!r})\n"
        "import pytest\n"
        "import websockets\n"
        "from test_server import ws_server\n\n"
        "@pytest.mark.asyncio\n"
        "async def test_fixture_behavior(ws_server):\n"
        "    async with websockets.connect('ws://localhost:8765') as ws:\n"
        "        await ws.send('nop')\n"
        "        assert await ws.recv() == '90'\n"
    )
    result = subprocess.run(
        [sys.executable, "-m", "pytest", str(trusted_test), "-x", "--tb=short"],
        cwd=str(tmp_path),
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "The submitted ws_server fixture does not set up a working server and "
        f"tear it down correctly:\n{result.stdout}\n{result.stderr}"
    )


def test_response_log_exists():
    """Preserve the original response-log existence assertion."""
    assert os.path.isfile(LOG_FILE), f"Response log {LOG_FILE} is missing."


def test_response_log_content():
    """Preserve the original response-log content assertions."""
    with open(LOG_FILE, "r") as f:
        hex_data = f.read().strip()

    assert hex_data, "Response log is empty."
    try:
        code = bytes.fromhex(hex_data)
    except ValueError:
        pytest.fail("Response log does not contain valid hex-encoded data.")

    assert b'\x0f\x05' in code, (
        "Machine code does not contain a syscall instruction (0f 05)."
    )
    assert b'\x2a' in code, (
        "Machine code does not contain the value 42 (0x2a)."
    )
    assert b'\x3c' in code, (
        "Machine code does not contain the sys_exit syscall number 60 (0x3c)."
    )


def verify_exit42_machine_code(code):
    """Symbolically check a small straight-line x86-64 exit(42) payload."""
    from capstone import Cs, CS_ARCH_X86, CS_MODE_64, CS_OP_IMM, CS_OP_REG

    assert 0 < len(code) <= 64, "The assembled payload is not minimal."

    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    instructions = list(md.disasm(code, 0))
    assert instructions, "The server response does not decode as x86-64 code."
    assert sum(i.size for i in instructions) == len(code), (
        "The response contains bytes that are not part of valid x86-64 instructions."
    )
    assert instructions[-1].mnemonic == "syscall", (
        "The payload must end with the exit syscall."
    )
    assert sum(i.mnemonic == "syscall" for i in instructions) == 1, (
        "The payload must contain exactly one syscall."
    )

    aliases = {
        "rax": "rax", "eax": "rax", "rbx": "rbx", "ebx": "rbx",
        "rcx": "rcx", "ecx": "rcx", "rdx": "rdx", "edx": "rdx",
        "rsi": "rsi", "esi": "rsi", "rdi": "rdi", "edi": "rdi",
        "rbp": "rbp", "ebp": "rbp", "rsp": "rsp", "esp": "rsp",
        "r8": "r8", "r8d": "r8", "r9": "r9", "r9d": "r9",
        "r10": "r10", "r10d": "r10", "r11": "r11", "r11d": "r11",
        "r12": "r12", "r12d": "r12", "r13": "r13", "r13d": "r13",
        "r14": "r14", "r14d": "r14", "r15": "r15", "r15d": "r15",
    }
    state = {}
    stack = []

    def reg_info(insn, operand):
        name = insn.reg_name(operand.reg)
        assert name in aliases and operand.size in (4, 8), (
            f"Unsupported register form in instruction: {insn.mnemonic} {insn.op_str}"
        )
        return aliases[name], operand.size

    def read_operand(insn, operand):
        if operand.type == CS_OP_IMM:
            return operand.imm
        if operand.type == CS_OP_REG:
            reg, _ = reg_info(insn, operand)
            return state.get(reg)
        pytest.fail(f"Memory operands are not needed for a minimal exit payload: {insn.mnemonic} {insn.op_str}")

    def write_reg(insn, operand, value):
        reg, size = reg_info(insn, operand)
        if value is not None:
            value &= (1 << (size * 8)) - 1
        state[reg] = value

    for insn in instructions[:-1]:
        ops = insn.operands
        mnemonic = insn.mnemonic
        assert mnemonic in {"mov", "movabs", "xor", "add", "sub", "push", "pop"}, (
            f"Non-minimal or unsafe instruction in payload: {mnemonic} {insn.op_str}"
        )

        if mnemonic in {"mov", "movabs"}:
            assert len(ops) == 2 and ops[0].type == CS_OP_REG
            write_reg(insn, ops[0], read_operand(insn, ops[1]))
        elif mnemonic == "xor":
            assert len(ops) == 2 and ops[0].type == CS_OP_REG and ops[1].type == CS_OP_REG
            left, _ = reg_info(insn, ops[0])
            right, _ = reg_info(insn, ops[1])
            assert left == right, "Only register-clearing xor is needed here."
            write_reg(insn, ops[0], 0)
        elif mnemonic in {"add", "sub"}:
            assert len(ops) == 2 and ops[0].type == CS_OP_REG
            reg, _ = reg_info(insn, ops[0])
            old = state.get(reg)
            value = read_operand(insn, ops[1])
            assert old is not None and value is not None, "Arithmetic uses an unknown value."
            write_reg(insn, ops[0], old + value if mnemonic == "add" else old - value)
        elif mnemonic == "push":
            assert len(ops) == 1
            value = read_operand(insn, ops[0])
            assert value is not None, "push uses an unknown value."
            stack.append(value)
        elif mnemonic == "pop":
            assert len(ops) == 1 and ops[0].type == CS_OP_REG and stack
            write_reg(insn, ops[0], stack.pop())

    assert state.get("rax") == 60, (
        "The payload does not set rax/eax to the x86-64 sys_exit number 60."
    )
    assert state.get("rdi") == 42, (
        "The payload does not set rdi/edi to exit status 42."
    )


@pytest.mark.asyncio
async def test_client_uses_websocket_and_writes_exact_server_response():
    """Run client.py against a trusted server and validate the sent program."""
    assert os.path.isfile(CLIENT_FILE), f"Client file {CLIENT_FILE} is missing."
    assert not os.path.islink(CLIENT_FILE), "client.py must be a regular submitted file."

    import websockets
    from pwn import asm, context

    context.clear(arch="amd64")
    received = []
    replies = []

    async def handler(websocket):
        async for message in websocket:
            assert isinstance(message, str), "The assembly payload must be sent as text."
            received.append(message)
            try:
                machine_code = asm(message)
                reply = machine_code.hex()
            except Exception:
                reply = "ERROR"
            replies.append(reply)
            await websocket.send(reply)

    if os.path.lexists(LOG_FILE):
        os.unlink(LOG_FILE)

    ws = await websockets.serve(handler, "localhost", 8765)
    try:
        proc = await asyncio.create_subprocess_exec(
            sys.executable,
            CLIENT_FILE,
            cwd=PROJECT,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            pytest.fail("client.py did not finish within 20 seconds.")
    finally:
        ws.close()
        await ws.wait_closed()

    assert proc.returncode == 0, (
        f"client.py failed:\n{stdout.decode(errors='replace')}\n"
        f"{stderr.decode(errors='replace')}"
    )
    assert len(received) == 1, "client.py must send exactly one assembly payload over WebSockets."
    assert len(replies) == 1 and replies[0] != "ERROR", (
        "The submitted assembly could not be assembled by pwntools."
    )
    assert os.path.isfile(LOG_FILE), "client.py did not generate response.log."

    with open(LOG_FILE, "r") as f:
        raw_log = f.read()
    assert raw_log == replies[0], (
        "response.log must contain exactly the hex string received from the WebSocket server."
    )

    try:
        code = bytes.fromhex(raw_log)
    except ValueError:
        pytest.fail("The server response written by client.py is not valid hex.")
    verify_exit42_machine_code(code)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
