#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess


def get_expected_interface():
    log_file = "/home/user/inventory_dump.log"
    sys_mock_dir = "/home/user/sys_mock"

    assert os.path.exists(log_file), f"{log_file} is missing."

    target_mac = None
    with open(log_file, "r") as f:
        for line in f:
            if "ROLE: storage_backend" in line:
                match = re.search(r"MAC:\s*([0-9a-fA-F:]+)", line)
                if match:
                    target_mac = match.group(1).lower()
                    break

    assert target_mac is not None, "Could not find storage_backend MAC in inventory_dump.log."

    target_iface = None
    for iface in os.listdir(sys_mock_dir):
        addr_file = os.path.join(sys_mock_dir, iface, "address")
        if os.path.isfile(addr_file):
            with open(addr_file, "r") as f:
                mac = f.read().strip().lower()
                if mac == target_mac:
                    target_iface = iface
                    break

    assert target_iface is not None, f"Could not find interface for MAC {target_mac} in {sys_mock_dir}."
    return target_iface


def generator_candidates():
    interpreters = {
        ".py": "python3",
        ".rb": "ruby",
        ".pl": "perl",
    }
    return [
        (f"/home/user/build_routes{ext}", interpreter)
        for ext, interpreter in interpreters.items()
        if os.path.isfile(f"/home/user/build_routes{ext}")
    ]


def run_generator(script_path, interpreter, expected_iface):
    output_path = "/home/user/apply_routes.sh"
    try:
        os.unlink(output_path)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [interpreter, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    if result.returncode != 0 or not os.path.isfile(output_path):
        return False

    with open(output_path, "r") as f:
        content = f.read().strip().splitlines()

    route_pattern = rf"ip route add 10\.50\.0\.0/16 via 10\.50\.0\.1 dev {re.escape(expected_iface)}"
    env_pattern = rf"echo\s+['\"]?(export\s+)?STORAGE_IFACE={re.escape(expected_iface)}['\"]?\s+>>\s+/home/user/\.bash_profile"
    return (
        any(re.search(route_pattern, line) for line in content)
        and any(re.search(env_pattern, line) for line in content)
    )


def test_build_routes_script_exists():
    allowed_extensions = ['.py', '.rb', '.pl']
    found = False
    for ext in allowed_extensions:
        if os.path.isfile(f"/home/user/build_routes{ext}"):
            found = True
            break
    assert found, "build_routes script (with .py, .rb, or .pl extension) is missing."


def test_generator_dynamically_creates_apply_routes():
    inventory_path = "/home/user/inventory_dump.log"
    alternate_addr_path = "/home/user/sys_mock/enp2s0/address"

    with open(inventory_path, "rb") as f:
        original_inventory = f.read()
    with open(alternate_addr_path, "rb") as f:
        original_alternate_addr = f.read()

    old_storage_line = b"MAC: A1:B2:C3:D4:E5:F6 | ROLE: storage_backend"
    new_storage_line = b"MAC: DE:AD:BE:EF:00:42 | ROLE: storage_backend"
    assert old_storage_line in original_inventory, "Expected storage_backend fixture line is missing."

    errors = []
    for script_path, interpreter in generator_candidates():
        try:
            with open(inventory_path, "wb") as f:
                f.write(original_inventory.replace(old_storage_line, new_storage_line))
            with open(alternate_addr_path, "w") as f:
                f.write("de:ad:be:ef:00:42\n")

            if not run_generator(script_path, interpreter, "enp2s0"):
                errors.append(f"{script_path} did not generate correct output for changed inputs")
                continue

            with open(inventory_path, "wb") as f:
                f.write(original_inventory)
            with open(alternate_addr_path, "wb") as f:
                f.write(original_alternate_addr)

            original_iface = get_expected_interface()
            if not run_generator(script_path, interpreter, original_iface):
                errors.append(f"{script_path} did not generate correct output for original inputs")
                continue

            return
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{script_path}: {exc}")
        finally:
            with open(inventory_path, "wb") as f:
                f.write(original_inventory)
            with open(alternate_addr_path, "wb") as f:
                f.write(original_alternate_addr)

    assert False, "No generator dynamically created apply_routes.sh: " + "; ".join(errors)


def test_apply_routes_sh():
    script_path = "/home/user/apply_routes.sh"
    assert os.path.isfile(script_path), f"{script_path} was not generated."

    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 3, f"{script_path} must contain exactly the shebang and two commands."
    assert content[0] == "#!/bin/bash", f"First line of {script_path} is not #!/bin/bash."

    target_iface = get_expected_interface()

    route_cmd_pattern = rf"ip route add 10\.50\.0\.0/16 via 10\.50\.0\.1 dev {target_iface}"
    route_found = any(re.search(route_cmd_pattern, line) for line in content)
    assert route_found, f"Expected route command for {target_iface} not found in {script_path}."

    env_cmd_pattern = rf"echo\s+['\"]?(export\s+)?STORAGE_IFACE={target_iface}['\"]?\s+>>\s+/home/user/\.bash_profile"
    env_found = any(re.search(env_cmd_pattern, line) for line in content)
    assert env_found, f"Expected command to append STORAGE_IFACE={target_iface} to .bash_profile not found in {script_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
