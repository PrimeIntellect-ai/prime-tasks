#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import time
import urllib.request

import pytest

APP = "/home/user/matrix_app"
LIBS = os.path.join(APP, "libs")
TRACE_DIR = "/tmp/deploy-tool-wrappers"
TRACE_LOG = "/tmp/deploy-tool-trace.log"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def symbol_size(path, symbol):
    result = run(["/usr/bin/readelf", "-Ws", path])
    assert result.returncode == 0, result.stderr
    sizes = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 8 and fields[-1] == symbol and fields[3] == "FUNC":
            sizes.append(int(fields[2], 10))
    assert sizes, f"Could not find {symbol} in {path}"
    return max(sizes)


def make_wrapper(tool):
    real_tool = f"/usr/bin/{tool}"
    assert os.path.isfile(real_tool), f"Missing required tool {real_tool}"
    wrapper = os.path.join(TRACE_DIR, tool)
    with open(wrapper, "w") as f:
        f.write("#!/bin/bash\n")
        f.write(f"printf '%s\\t' '{tool}' >> '{TRACE_LOG}'\n")
        f.write(f"printf '%q ' \"$@\" >> '{TRACE_LOG}'\n")
        f.write(f"printf '\\n' >> '{TRACE_LOG}'\n")
        f.write(f"exec '{real_tool}' \"$@\"\n")
    os.chmod(wrapper, 0o755)


@pytest.fixture(scope="module", autouse=True)
def execute_deployment():
    deploy_script = os.path.join(APP, "deploy.sh")
    assert os.path.isfile(deploy_script), f"Deployment script {deploy_script} does not exist."
    assert os.stat(deploy_script).st_mode & stat.S_IXUSR, \
        f"Deployment script {deploy_script} is not executable."

    expected_sizes = {
        "libcompute_v1.so": 65,
        "libcompute_v2.so": 128,
        "libcompute_v3.so": 256,
    }
    measured = {
        name: symbol_size(os.path.join(LIBS, name), "compute_matrix")
        for name in expected_sizes
    }
    assert measured == expected_sizes, f"Unexpected input library symbol sizes: {measured}"
    derived = [name for name, size in measured.items() if size == 128]
    assert derived == ["libcompute_v2.so"], \
        f"Expected exactly one 128-byte compute_matrix implementation, got {derived}"

    subprocess.run(["pkill", "-x", "server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "socat"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    for path in (os.path.join(APP, "server"),
                 os.path.join(APP, "abi_version.txt"),
                 os.path.join(LIBS, "libcompute.so")):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.makedirs(TRACE_DIR, exist_ok=True)
    try:
        os.unlink(TRACE_LOG)
    except FileNotFoundError:
        pass
    for tool in ("rustc", "nm", "readelf", "objdump", "socat"):
        make_wrapper(tool)

    env = os.environ.copy()
    env["PATH"] = TRACE_DIR + os.pathsep + env.get("PATH", "")
    with open("/tmp/deploy-execution.log", "w") as output:
        try:
            result = subprocess.run(
                [deploy_script], cwd=APP, env=env, stdin=subprocess.DEVNULL,
                stdout=output, stderr=subprocess.STDOUT, timeout=30
            )
        except subprocess.TimeoutExpired:
            pytest.fail("deploy.sh did not complete within 30 seconds")
    assert result.returncode == 0, \
        "deploy.sh exited with an error; see /tmp/deploy-execution.log"

    yield


def test_deploy_script_exists_and_executable():
    deploy_script = "/home/user/matrix_app/deploy.sh"
    assert os.path.isfile(deploy_script), f"Deployment script {deploy_script} does not exist."
    st = os.stat(deploy_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deployment script {deploy_script} is not executable."


def test_abi_version_file():
    abi_file = "/home/user/matrix_app/abi_version.txt"
    assert os.path.isfile(abi_file), f"ABI version file {abi_file} does not exist."
    with open(abi_file, "r") as f:
        content = f.read().strip()
    assert "libcompute_v2.so" in content, f"Expected 'libcompute_v2.so' in {abi_file}, got '{content}'."


def test_symlink_correct():
    symlink_path = "/home/user/matrix_app/libs/libcompute.so"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert target.endswith("libcompute_v2.so"), f"Symlink points to {target}, expected it to point to libcompute_v2.so."
    resolved = os.path.realpath(symlink_path)
    assert symbol_size(resolved, "compute_matrix") == 128, \
        "Selected library does not have a 128-byte compute_matrix symbol"


def test_server_compiled():
    server_bin = "/home/user/matrix_app/server"
    assert os.path.isfile(server_bin), f"Compiled server binary {server_bin} does not exist."
    st = os.stat(server_bin)
    assert bool(st.st_mode & stat.S_IXUSR), f"Server binary {server_bin} is not executable."
    with open(server_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server is not an ELF executable"

    dynamic = run(["/usr/bin/readelf", "-d", server_bin])
    assert dynamic.returncode == 0, dynamic.stderr
    assert "libcompute.so" in dynamic.stdout, \
        "server is not dynamically linked against libcompute.so"

    symbols = run(["/usr/bin/readelf", "-Ws", server_bin])
    assert symbols.returncode == 0, symbols.stderr
    assert any(line.split()[-1:] == ["compute_matrix"] and " UND " in line
               for line in symbols.stdout.splitlines()), \
        "server does not contain the expected compute_matrix FFI reference"


def test_rust_source_is_repaired_and_compiles():
    output = tempfile.mktemp(prefix="matrix-server-check-")
    try:
        result = run([
            "/usr/bin/rustc", "-L", LIBS, "src/main.rs", "-o", output
        ], cwd=APP)
        assert result.returncode == 0, \
            f"The repaired Rust source does not compile with the required command:\n{result.stderr}"
        assert os.path.isfile(output) and os.access(output, os.X_OK)
    finally:
        try:
            os.unlink(output)
        except FileNotFoundError:
            pass


def test_deploy_invoked_required_tools():
    assert os.path.isfile(TRACE_LOG), "deploy.sh did not invoke any monitored deployment tools"
    with open(TRACE_LOG) as f:
        lines = f.read().splitlines()

    rustc_lines = [line for line in lines if line.startswith("rustc\t")]
    assert rustc_lines, "deploy.sh did not invoke rustc"
    assert any("src/main.rs" in line and "server" in line and
               "/home/user/matrix_app/libs" in line and "-o" in line
               for line in rustc_lines), \
        "deploy.sh did not invoke rustc with the required source, library path, and output"

    inspection_lines = [line for line in lines
                        if line.startswith(("nm\t", "readelf\t", "objdump\t"))]
    assert inspection_lines, "deploy.sh did not invoke nm, readelf, or objdump"
    assert any("libcompute_v" in line and ".so" in line for line in inspection_lines), \
        "deploy.sh did not inspect the versioned shared libraries"

    socat_lines = [line for line in lines if line.startswith("socat\t")]
    assert socat_lines, "deploy.sh did not invoke socat"
    assert any("9090" in line and "8000" in line for line in socat_lines), \
        "socat was not configured to forward port 9090 to port 8000"


def test_server_and_reverse_proxy_processes_started():
    deadline = time.time() + 5
    server_seen = False
    proxy_seen = False
    while time.time() < deadline:
        servers = run(["pgrep", "-a", "server"])
        proxies = run(["pgrep", "-a", "socat"])
        server_seen = servers.returncode == 0 and bool(servers.stdout.strip())
        proxy_seen = (proxies.returncode == 0 and "9090" in proxies.stdout and
                      "8000" in proxies.stdout)
        if server_seen and proxy_seen:
            break
        time.sleep(0.2)
    assert server_seen, "The compiled server process was not started"
    assert proxy_seen, "The socat reverse proxy process was not started correctly"


def test_reverse_proxy_and_server_response():
    url = "http://127.0.0.1:9090"
    max_retries = 5
    response_body = ""

    for _ in range(max_retries):
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=2) as response:
                response_body = response.read().decode("utf-8")
                break
        except Exception:
            time.sleep(1)
    else:
        pytest.fail(f"Failed to connect to {url} or receive a successful response. Ensure the server and socat proxy are running.")

    assert "Matrix Computed" in response_body, f"Expected 'Matrix Computed' in response, got '{response_body}'."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
