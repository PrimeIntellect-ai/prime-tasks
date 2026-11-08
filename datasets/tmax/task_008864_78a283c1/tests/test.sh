#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import http.server
import json
import os
import random
import signal
import socketserver
import subprocess
import threading
import time
import uuid

SERVICES = [
    {"name": "service_auth", "depends_on": ["service_db", "service_cache"], "config_data": "auth_config_v2"},
    {"name": "service_db", "depends_on": ["service_network"], "config_data": "db_config_v2"},
    {"name": "service_cache", "depends_on": ["service_network"], "config_data": "cache_config_v2"},
    {"name": "service_api", "depends_on": ["service_auth", "service_logic"], "config_data": "api_config_v2"},
    {"name": "service_network", "depends_on": [], "config_data": "network_config_v2"},
    {"name": "service_logic", "depends_on": ["service_db"], "config_data": "logic_config_v2"}
]


def get_expected_hashes(services=SERVICES):
    return {
        svc["name"]: hashlib.sha256(svc["config_data"].encode("utf-8")).hexdigest()
        for svc in services
    }


def valid_order(content, services):
    order = [s.strip() for s in content.strip().split(",") if s.strip()]
    names = [svc["name"] for svc in services]
    assert len(order) == len(names), "build_order.txt does not contain all services exactly once"
    assert set(order) == set(names), "build_order.txt contains missing, duplicate, or unknown services"
    positions = {name: i for i, name in enumerate(order)}
    for svc in services:
        for dependency in svc["depends_on"]:
            assert positions[dependency] < positions[svc["name"]], (
                f"{dependency} must be before {svc['name']}"
            )


def test_build_order_txt():
    build_order_path = "/home/user/build_order.txt"
    assert os.path.isfile(build_order_path), f"Missing {build_order_path}"
    with open(build_order_path, "r") as f:
        content = f.read().strip()

    order = [s.strip() for s in content.split(",")]
    assert len(order) == len(SERVICES), "build_order.txt does not contain all services"

    def index_of(svc):
        assert svc in order, f"{svc} missing from build_order.txt"
        return order.index(svc)

    assert index_of("service_network") < index_of("service_db"), "network must be before db"
    assert index_of("service_network") < index_of("service_cache"), "network must be before cache"
    assert index_of("service_db") < index_of("service_auth"), "db must be before auth"
    assert index_of("service_db") < index_of("service_logic"), "db must be before logic"
    assert index_of("service_cache") < index_of("service_auth"), "cache must be before auth"
    assert index_of("service_auth") < index_of("service_api"), "auth must be before api"
    assert index_of("service_logic") < index_of("service_api"), "logic must be before api"


def test_makefile_structure():
    makefile_path = "/home/user/Makefile"
    assert os.path.isfile(makefile_path), f"Missing {makefile_path}"
    with open(makefile_path, "r") as f:
        lines = f.readlines()

    first_target_line = None
    for line in lines:
        if line.strip() and not line.startswith("\t") and not line.startswith("#"):
            first_target_line = line
            break

    assert first_target_line is not None, "Makefile has no targets"
    assert first_target_line.startswith("all:"), "First target in Makefile must be 'all:'"
    for svc in SERVICES:
        assert svc["name"] in first_target_line, f"{svc['name']} missing from 'all' target"


def test_make_execution_and_build_files():
    makefile_path = "/home/user/Makefile"
    assert os.path.isfile(makefile_path), f"Missing {makefile_path}"
    result = subprocess.run(["make", "-C", "/home/user"], capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with output:\n{result.stderr}"

    expected_hashes = get_expected_hashes()
    for svc in SERVICES:
        build_file = f"/home/user/{svc['name']}.build"
        assert os.path.isfile(build_file), f"Missing build file {build_file} after running make"
        with open(build_file, "r") as f:
            content = f.read().strip()
        expected_hash = expected_hashes[svc["name"]]
        assert content == expected_hash, (
            f"Hash mismatch in {build_file}: expected {expected_hash}, got {content}"
        )


def stop_existing_mock_api():
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                command = f.read().replace(b"\0", b" ")
            if b"/home/user/mock_api.py" in command:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


def find_submission_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith(".py") and os.path.realpath(path) != "/home/user/mock_api.py":
                scripts.append(path)
    return sorted(scripts)


def check_dynamic_artifacts(services):
    with open("/home/user/build_order.txt", "r") as f:
        valid_order(f.read(), services)

    with open("/home/user/Makefile", "r") as f:
        lines = f.read().splitlines()

    meaningful = [line for line in lines if line.strip() and not line.lstrip().startswith("#")]
    target_lines = [line for line in meaningful if not line.startswith("\t") and ":" in line]
    assert target_lines, "Makefile has no targets"

    first_name, first_deps = target_lines[0].split(":", 1)
    assert first_name.strip() == "all", "The first Makefile target is not all"
    all_dependencies = first_deps.split()
    expected_names = [svc["name"] for svc in services]
    assert len(all_dependencies) == len(expected_names)
    assert set(all_dependencies) == set(expected_names), "all target does not list exactly all API services"

    targets = {}
    for index, line in enumerate(lines):
        if line.startswith("\t") or line.lstrip().startswith("#") or ":" not in line:
            continue
        name, dependencies = line.split(":", 1)
        name = name.strip()
        if name:
            targets[name] = (dependencies.split(), index)

    expected_hashes = get_expected_hashes(services)
    for svc in services:
        name = svc["name"]
        assert name in targets, f"Missing Makefile target {name}"
        dependencies, index = targets[name]
        assert len(dependencies) == len(svc["depends_on"])
        assert set(dependencies) == set(svc["depends_on"]), f"Wrong dependencies for {name}"
        assert index + 1 < len(lines), f"Missing recipe for {name}"
        expected_recipe = f'\techo "{expected_hashes[name]}" > {name}.build'
        assert lines[index + 1] == expected_recipe, f"Recipe for {name} is not exactly as required"

    result = subprocess.run(
        ["make", "-C", "/home/user"], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"dynamic make failed:\n{result.stdout}\n{result.stderr}"
    for svc in services:
        path = f"/home/user/{svc['name']}.build"
        assert os.path.isfile(path), f"Missing dynamically generated {path}"
        with open(path, "r") as f:
            assert f.read().strip() == expected_hashes[svc["name"]]


def test_python_script_queries_api_and_generates_dynamic_outputs():
    scripts = find_submission_scripts()
    assert scripts, "No submitted Python script exists under /home/user"

    token = uuid.uuid4().hex[:10]
    services = [
        {"name": f"base_{token}", "depends_on": [], "config_data": uuid.uuid4().hex},
        {"name": f"store_{token}", "depends_on": [f"base_{token}"], "config_data": uuid.uuid4().hex},
        {"name": f"cache_{token}", "depends_on": [f"base_{token}"], "config_data": uuid.uuid4().hex},
        {"name": f"logic_{token}", "depends_on": [f"store_{token}", f"cache_{token}"], "config_data": uuid.uuid4().hex},
        {"name": f"front_{token}", "depends_on": [f"logic_{token}"], "config_data": uuid.uuid4().hex}
    ]
    random.SystemRandom().shuffle(services)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/api/v1/dependencies":
                body = json.dumps(services).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, format, *args):
            pass

    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    stop_existing_mock_api()
    server = ReusableTCPServer(("127.0.0.1", 9090), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    errors = []
    try:
        for script in scripts:
            for path in ["/home/user/Makefile", "/home/user/build_order.txt"]:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            for svc in services:
                try:
                    os.remove(f"/home/user/{svc['name']}.build")
                except FileNotFoundError:
                    pass

            try:
                result = subprocess.run(
                    ["python3", script], cwd="/home/user", capture_output=True,
                    text=True, timeout=15
                )
                assert result.returncode == 0, (
                    f"script exited {result.returncode}: {result.stdout}\n{result.stderr}"
                )
                assert os.path.isfile("/home/user/Makefile"), "script did not generate Makefile"
                assert os.path.isfile("/home/user/build_order.txt"), "script did not generate build_order.txt"
                check_dynamic_artifacts(services)
                return
            except Exception as exc:
                errors.append(f"{script}: {exc}")
        raise AssertionError("No submitted Python script handled live API data correctly:\n" + "\n".join(errors))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
