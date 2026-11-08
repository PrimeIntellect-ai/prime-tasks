#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import subprocess
import uuid
import pytest


def test_rust_project_execution_and_output():
    automator_dir = "/home/user/automator"
    spec_file = "/home/user/deploy_spec.txt"
    mock_file = "/home/user/qemu_serial_mock.sh"
    vm_state_file = "/home/user/vm_state.conf"
    route_file = "/home/user/route-eth0.conf"

    # Ensure the Rust project directory exists
    assert os.path.isdir(automator_dir), f"Rust project directory missing: {automator_dir}"

    # Use fresh values so hardcoded output cannot pass.
    nonce = uuid.uuid4().hex
    tz = f"TestZone/{nonce[:10]}"
    loc = f"zz_{nonce[10:18]}.UTF-8"
    ip = f"10.{int(nonce[0:2], 16) % 250 + 1}.{int(nonce[2:4], 16) % 250 + 1}.{int(nonce[4:6], 16) % 250 + 1}/24"
    gw = f"10.{int(nonce[0:2], 16) % 250 + 1}.{int(nonce[2:4], 16) % 250 + 1}.1"
    with open(spec_file, "w") as f:
        f.write(f"{tz}\n{loc}\n{ip}\n{gw}\n")

    # Read the expected values from the spec file
    assert os.path.isfile(spec_file), f"Spec file missing: {spec_file}"
    with open(spec_file, "r") as f:
        spec_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(spec_lines) >= 4, "deploy_spec.txt does not have enough lines."
    tz, loc, ip, gw = spec_lines[:4]

    # Install an instrumented serial mock. Its completion token is emitted only
    # after all four requested values have been received in prompt order.
    start_marker = f"/tmp/qemu-start-{uuid.uuid4().hex}"
    done_marker = f"/tmp/qemu-done-{uuid.uuid4().hex}"
    token = uuid.uuid4().hex
    mock_script = r'''#!/bin/bash
set -u
start_marker=__START__
done_marker=__DONE__
token=__TOKEN__
printf '%s\n' "$token" > "$start_marker"
mapfile -t expected < /home/user/deploy_spec.txt
[[ ${#expected[@]} -ge 4 ]] || exit 30
printf 'Timezone:\n'
IFS= read -r tz || exit 31
printf 'Locale:\n'
IFS= read -r loc || exit 32
printf 'IP:\n'
IFS= read -r ip || exit 33
printf 'Gateway:\n'
IFS= read -r gw || exit 34
[[ "$tz" == "${expected[0]}" ]] || exit 41
[[ "$loc" == "${expected[1]}" ]] || exit 42
[[ "$ip" == "${expected[2]}" ]] || exit 43
[[ "$gw" == "${expected[3]}" ]] || exit 44
printf 'TZ=%s\nLOCALE=%s\nIP=%s\nGW=%s\n' "$tz" "$loc" "$ip" "$gw" > /home/user/vm_state.conf
printf '%s\n' "$token" > "$done_marker"
printf 'Done.\n'
'''
    mock_script = mock_script.replace("__START__", shlex.quote(start_marker))
    mock_script = mock_script.replace("__DONE__", shlex.quote(done_marker))
    mock_script = mock_script.replace("__TOKEN__", shlex.quote(token))
    with open(mock_file, "w") as f:
        f.write(mock_script)
    os.chmod(mock_file, 0o755)

    # Clean up previous state files and trace markers to ensure this execution creates them.
    for path in (vm_state_file, route_file, start_marker, done_marker):
        if os.path.exists(path):
            os.remove(path)

    # Run the Rust program
    try:
        result = subprocess.run(
            ["cargo", "run"],
            cwd=automator_dir,
            capture_output=True,
            text=True,
            timeout=30
        )
        assert result.returncode == 0, f"'cargo run' failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    except FileNotFoundError:
        pytest.fail("Cargo is not installed or not found in PATH.")
    except subprocess.TimeoutExpired:
        pytest.fail("The Rust program timed out. Ensure it correctly interacts with the mock script and flushes I/O.")

    assert os.path.isfile(start_marker), "The Rust program did not spawn /home/user/qemu_serial_mock.sh."
    with open(start_marker, "r") as f:
        assert f.read().strip() == token, "Invalid serial mock invocation marker."
    assert os.path.isfile(done_marker), "The serial mock did not receive all four correct parameters in prompt order."
    with open(done_marker, "r") as f:
        assert f.read().strip() == token, "Invalid serial mock completion marker."

    # Check vm_state.conf
    assert os.path.isfile(vm_state_file), f"The mock script did not create {vm_state_file}. The Rust program may not have completed the interaction successfully."
    with open(vm_state_file, "r") as f:
        vm_state_content = f.read()

    assert f"TZ={tz}" in vm_state_content, f"Expected TZ={tz} in {vm_state_file}"
    assert f"LOCALE={loc}" in vm_state_content, f"Expected LOCALE={loc} in {vm_state_file}"
    assert f"IP={ip}" in vm_state_content, f"Expected IP={ip} in {vm_state_file}"
    assert f"GW={gw}" in vm_state_content, f"Expected GW={gw} in {vm_state_file}"

    # Check route-eth0.conf
    assert os.path.isfile(route_file), f"The Rust program did not create {route_file}."
    with open(route_file, "r") as f:
        route_content = f.read().strip()

    expected_route = f"default via {gw} dev eth0"
    assert route_content == expected_route, f"Content of {route_file} is incorrect. Expected: '{expected_route}', but got: '{route_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
