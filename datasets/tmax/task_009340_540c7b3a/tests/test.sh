#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'CLIENT_EOF' > /tmp/dynamic_vm_client.py
import asyncio
import base64
import json
import secrets
import websockets


def encode(instructions):
    data = bytearray()
    for opcode, operand in instructions:
        data.extend((opcode, operand & 0xff))
    return bytes(data)


def oracle(binary_data):
    stack = []
    pc = 0
    while pc < len(binary_data):
        opcode = binary_data[pc]
        operand_byte = binary_data[pc + 1]
        operand = operand_byte if operand_byte < 128 else operand_byte - 256
        pc += 2

        if opcode == 1:
            stack.append(operand)
            if len(stack) > 10:
                stack.pop(0)
        elif opcode == 2:
            a = stack.pop()
            b = stack.pop()
            stack.append(b + a)
        elif opcode == 3:
            a = stack.pop()
            b = stack.pop()
            stack.append(b * a)
        elif opcode == 4:
            positions = stack.pop()
            if stack:
                positions %= len(stack)
                if positions:
                    stack[:] = stack[-positions:] + stack[:-positions]
        elif opcode == 5:
            break
    return stack


def make_random_program(rng):
    instructions = []
    depth = 0
    for _ in range(rng.randrange(28, 55)):
        choices = [1, 1, 1]
        if depth >= 2:
            choices.extend([2, 3, 4])
        opcode = rng.choice(choices)
        if opcode == 1:
            instructions.append((1, rng.randrange(-128, 128)))
            depth = min(10, depth + 1)
        elif opcode in (2, 3):
            instructions.append((opcode, rng.randrange(-128, 128)))
            depth -= 1
        else:
            instructions.append((4, rng.randrange(-128, 128)))
            depth -= 1

    if rng.randrange(2):
        instructions.append((5, rng.randrange(-128, 128)))
        # These instructions must be ignored after HALT.
        instructions.extend([(1, rng.randrange(-128, 128)), (2, 0)])
    return encode(instructions)


async def run():
    rng = secrets.SystemRandom()
    cases = [
        # Original verifier's program and expected result.
        encode([(1, 5), (1, 10), (1, -2), (2, 0), (3, 0),
                (1, 1), (4, 0), (5, 0)]),
        # Signed operands and arithmetic.
        encode([(1, -128), (1, -3), (3, 77), (1, 127), (2, -22)]),
        # Positive and negative non-trivial rotations.
        encode([(1, 1), (1, 2), (1, 3), (1, 4), (1, 2), (4, 0)]),
        encode([(1, 1), (1, 2), (1, 3), (1, -1), (4, 0)]),
        # RingStack capacity eviction.
        encode([(1, value) for value in range(13)]),
        # HALT must prevent execution of trailing bytecode.
        encode([(1, 9), (1, 4), (5, 0), (1, 100), (3, 0)]),
    ]
    cases.extend(make_random_program(rng) for _ in range(14))

    for index, bytecode in enumerate(cases):
        expected = oracle(bytecode)
        payload = base64.b64encode(bytecode).decode('ascii')
        async with websockets.connect('ws://localhost:8765') as websocket:
            await websocket.send(payload)
            raw_response = await asyncio.wait_for(websocket.recv(), timeout=3)
            actual = json.loads(raw_response)
            assert isinstance(actual, list), (index, actual)
            assert all(isinstance(item, int) and not isinstance(item, bool) for item in actual), (index, actual)
            assert actual == expected, (index, expected, actual, bytecode.hex())
            # The service is required to close each connection after responding.
            await asyncio.wait_for(websocket.wait_closed(), timeout=2)

    print('DYNAMIC_SUCCESS')


asyncio.run(run())
CLIENT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import time
import pytest


def test_venv_exists():
    """Test that the Python 3 virtual environment is set up."""
    python_path = "/home/user/venv/bin/python"
    assert os.path.isfile(python_path), f"Virtual environment Python not found at {python_path}"
    result = subprocess.run(
        [python_path, "-c", "import websockets"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"websockets is not installed in the virtual environment: {result.stderr}"


def test_files_created():
    """Test that the required files are created."""
    assert os.path.isfile("/home/user/modern_vm.py"), "modern_vm.py is missing."
    assert os.path.isfile("/home/user/start_server.sh"), "start_server.sh is missing."


def test_server_and_vm_logic():
    """Start the submitted server and exercise the VM over sequential connections."""
    os.chmod("/home/user/start_server.sh", 0o755)
    subprocess.run(
        ["/bin/bash", "/home/user/start_server.sh"],
        check=True,
        timeout=10,
    )
    time.sleep(2)

    pid_file = "/home/user/vm.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} was not created by start_server.sh"
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer PID: {pid_str}"
    pid = int(pid_str)

    try:
        try:
            os.kill(pid, 0)
        except OSError:
            pytest.fail(f"Process with PID {pid} from {pid_file} is not running.")

        # Preserve the original fixed behavioral assertion.
        verify_script = "/home/user/verify.py"
        venv_python = "/home/user/venv/bin/python"
        assert os.path.isfile(verify_script), f"Verification script {verify_script} is missing."
        fixed_result = subprocess.run(
            [venv_python, verify_script],
            capture_output=True,
            text=True,
            timeout=10,
        )
        fixed_output = fixed_result.stdout.strip() + "\n" + fixed_result.stderr.strip()
        assert fixed_result.returncode == 0, f"Verification failed. Output:\n{fixed_output}"
        assert "SUCCESS" in fixed_output, f"Expected SUCCESS in output, got:\n{fixed_output}"

        # Use fresh unpredictable programs covering all VM operations and many
        # sequential WebSocket connections. Expected states are independently
        # derived at verification time.
        dynamic_result = subprocess.run(
            [venv_python, "/tmp/dynamic_vm_client.py"],
            capture_output=True,
            text=True,
            timeout=45,
        )
        dynamic_output = dynamic_result.stdout.strip() + "\n" + dynamic_result.stderr.strip()
        assert dynamic_result.returncode == 0, f"Dynamic VM verification failed:\n{dynamic_output}"
        assert "DYNAMIC_SUCCESS" in dynamic_output, f"Dynamic verification did not complete:\n{dynamic_output}"
    finally:
        try:
            os.kill(pid, 15)
        except OSError:
            pass

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
