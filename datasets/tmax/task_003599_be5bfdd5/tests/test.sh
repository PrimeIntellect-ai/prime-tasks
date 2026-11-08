#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import pwd
import secrets
import pytest

HOME = "/home/user"
GENERATED = ["aggregated_flows.txt", "savings.log", "update_routes.sh", "cost_optimizer"]

def run_user(argv):
    account = pwd.getpwnam("user")
    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    env = os.environ.copy()
    env["HOME"] = HOME
    return subprocess.run(argv, cwd=HOME, env=env, preexec_fn=demote,
                          check=True, timeout=30, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True)

def clear_generated():
    for name in GENERATED:
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            assert not os.path.isdir(path), f"Expected a file, not directory: {path}"
            os.unlink(path)

def parse_aggregated():
    parsed = {}
    with open(os.path.join(HOME, "aggregated_flows.txt")) as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.split()
            assert len(parts) == 3
            parsed[parts[0]] = {"bytes": int(parts[2]), "interface": parts[1]}
    return parsed

def check_challenge(expected_flows, expected_savings, expected_routes):
    assert parse_aggregated() == expected_flows
    with open(os.path.join(HOME, "savings.log")) as f:
        assert f.read().strip() == f"Total Savings: ${expected_savings:.2f}"
    route_path = os.path.join(HOME, "update_routes.sh")
    assert os.path.isfile(route_path)
    assert os.stat(route_path).st_mode & stat.S_IXUSR
    with open(route_path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines[0] == "#!/bin/bash"
    assert set(lines[1:]) == expected_routes

def test_pipeline_and_implementations_execute():
    required = ["aggregate_flows.sh", "cost_optimizer.c", "run_optimization.sh"]
    for name in required:
        assert os.path.isfile(os.path.join(HOME, name)), f"Missing /home/user/{name}"

    input_names = ["raw_flows.log", "pricing.csv", "allowed_routes.txt"]
    backups = {}
    for name in input_names:
        path = os.path.join(HOME, name)
        with open(path, "rb") as f:
            backups[name] = f.read()

    suffix = secrets.randbelow(180) + 20
    d1 = f"10.{suffix}.1.11"
    d2 = f"10.{suffix}.2.22"
    d3 = f"10.{suffix}.3.33"
    gb = 1073741824
    a = secrets.randbelow(6) + 3
    b = secrets.randbelow(6) + 4
    c = secrets.randbelow(6) + 2
    expected_flows = {
        d1: {"bytes": a * gb, "interface": "eth1"},
        d2: {"bytes": b * gb, "interface": "tun0"},
        d3: {"bytes": c * gb, "interface": "eth0"},
    }
    expected_savings = a * (0.11 - 0.02) + b * (0.07 - 0.03)
    expected_routes = {
        f"ip route replace {d1} dev wg0",
        f"ip route replace {d2} dev eth0",
        f"ip route replace {d3} dev eth0",
    }
    raw = (
        f"1700000000 10.0.0.1 {d1} {gb} eth1\n"
        f"1700000001 10.0.0.2 {d1} {(a-1)*gb} eth1\n"
        f"1700000002 10.0.0.3 {d2} {2*gb} tun0\n"
        f"1700000003 10.0.0.4 {d2} {(b-2)*gb} tun0\n"
        f"1700000004 10.0.0.5 {d3} {c*gb} eth0\n"
    )
    pricing = "eth0,0.03\neth1,0.11\ntun0,0.07\nwg0,0.02\n"
    allowed = f"{d1} eth1 wg0\n{d2} tun0 eth0\n{d3} eth0 eth1\n"

    try:
        for name, content in [("raw_flows.log", raw), ("pricing.csv", pricing),
                              ("allowed_routes.txt", allowed)]:
            with open(os.path.join(HOME, name), "w") as f:
                f.write(content)
            os.chmod(os.path.join(HOME, name), 0o644)

        clear_generated()
        run_user(["/bin/bash", os.path.join(HOME, "run_optimization.sh")])
        binary = os.path.join(HOME, "cost_optimizer")
        assert os.path.isfile(binary), "Master script did not create cost_optimizer"
        assert os.access(binary, os.X_OK), "Compiled optimizer is not executable"
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "cost_optimizer is not a compiled ELF binary"
        check_challenge(expected_flows, expected_savings, expected_routes)

        os.unlink(os.path.join(HOME, "aggregated_flows.txt"))
        run_user(["/bin/bash", os.path.join(HOME, "aggregate_flows.sh")])
        assert parse_aggregated() == expected_flows

        for name in ["savings.log", "update_routes.sh"]:
            path = os.path.join(HOME, name)
            if os.path.lexists(path):
                os.unlink(path)
        run_user([binary])
        check_challenge(expected_flows, expected_savings, expected_routes)

        compiled_test = os.path.join(HOME, ".verifier_compiled_optimizer")
        if os.path.lexists(compiled_test):
            os.unlink(compiled_test)
        run_user(["gcc", "-std=c11", os.path.join(HOME, "cost_optimizer.c"), "-o", compiled_test])
        for name in ["savings.log", "update_routes.sh"]:
            path = os.path.join(HOME, name)
            if os.path.lexists(path):
                os.unlink(path)
        run_user([compiled_test])
        check_challenge(expected_flows, expected_savings, expected_routes)
        os.unlink(compiled_test)
    finally:
        for name, content in backups.items():
            with open(os.path.join(HOME, name), "wb") as f:
                f.write(content)
            os.chmod(os.path.join(HOME, name), 0o644)
        clear_generated()
        run_user(["/bin/bash", os.path.join(HOME, "run_optimization.sh")])

def get_inputs():
    raw_flows_path = "/home/user/raw_flows.log"
    pricing_path = "/home/user/pricing.csv"
    allowed_routes_path = "/home/user/allowed_routes.txt"

    flows = {}
    if os.path.isfile(raw_flows_path):
        with open(raw_flows_path, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 5:
                    dst_ip = parts[2]
                    bytes_transferred = int(parts[3])
                    current_interface = parts[4]
                    if dst_ip not in flows:
                        flows[dst_ip] = {"bytes": 0, "interface": current_interface}
                    flows[dst_ip]["bytes"] += bytes_transferred

    pricing = {}
    if os.path.isfile(pricing_path):
        with open(pricing_path, "r") as f:
            for line in f:
                parts = line.strip().split(",")
                if len(parts) == 2:
                    pricing[parts[0]] = float(parts[1])

    allowed_routes = {}
    if os.path.isfile(allowed_routes_path):
        with open(allowed_routes_path, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    allowed_routes[parts[0]] = parts[1:]

    return flows, pricing, allowed_routes

def test_aggregated_flows():
    flows, _, _ = get_inputs()
    agg_path = "/home/user/aggregated_flows.txt"
    assert os.path.isfile(agg_path), f"Missing file: {agg_path}"

    with open(agg_path, "r") as f:
        lines = f.read().strip().split("\n")

    parsed_flows = {}
    for line in lines:
        if not line.strip():
            continue
        parts = line.strip().split()
        assert len(parts) == 3, f"Invalid format in aggregated_flows.txt: {line}"
        dst_ip, iface, total_bytes = parts[0], parts[1], int(parts[2])
        parsed_flows[dst_ip] = {"bytes": total_bytes, "interface": iface}

    assert parsed_flows == flows, f"Aggregated flows do not match expected: {parsed_flows} vs {flows}"

def test_savings_log():
    flows, pricing, allowed_routes = get_inputs()
    savings_path = "/home/user/savings.log"
    assert os.path.isfile(savings_path), f"Missing file: {savings_path}"

    total_savings = 0.0
    for dst_ip, data in flows.items():
        current_iface = data["interface"]
        total_bytes = data["bytes"]
        gb = total_bytes / 1073741824.0
        current_cost = gb * pricing.get(current_iface, 0.0)
        allowed = allowed_routes.get(dst_ip, [])
        cheapest_iface = min(allowed, key=lambda x: pricing.get(x, float('inf')))
        optimized_cost = gb * pricing.get(cheapest_iface, 0.0)
        total_savings += (current_cost - optimized_cost)

    expected_savings_str = f"Total Savings: ${total_savings:.2f}"
    with open(savings_path, "r") as f:
        content = f.read().strip()
    assert content == expected_savings_str, f"savings.log content '{content}' does not match expected '{expected_savings_str}'"

def test_update_routes_sh():
    flows, pricing, allowed_routes = get_inputs()
    script_path = "/home/user/update_routes.sh"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable"
    with open(script_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]
    assert lines[0] == "#!/bin/bash", f"update_routes.sh does not start with #!/bin/bash"

    expected_commands = set()
    for dst_ip, data in flows.items():
        allowed = allowed_routes.get(dst_ip, [])
        cheapest_iface = min(allowed, key=lambda x: pricing.get(x, float('inf')))
        expected_commands.add(f"ip route replace {dst_ip} dev {cheapest_iface}")
    actual_commands = set(lines[1:])
    assert actual_commands == expected_commands, f"update_routes.sh commands {actual_commands} do not match expected {expected_commands}"

def test_scripts_exist():
    assert os.path.isfile("/home/user/aggregate_flows.sh"), "Missing /home/user/aggregate_flows.sh"
    assert os.path.isfile("/home/user/cost_optimizer.c"), "Missing /home/user/cost_optimizer.c"
    assert os.path.isfile("/home/user/run_optimization.sh"), "Missing /home/user/run_optimization.sh"
    assert os.path.isfile("/home/user/cost_optimizer"), "Missing compiled binary /home/user/cost_optimizer"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
