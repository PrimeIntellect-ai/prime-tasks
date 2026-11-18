#!/bin/bash
set +e
mkdir -p /logs/verifier
REWARD=0
REAL_ENGINE="/tmp/query_engine.real.$$"
LOG_FILE="/tmp/query_engine.calls.$$"
TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
N1="Q${TOKEN}A"
N2="Q${TOKEN}B"
N3="Q${TOKEN}C"
M1="R${TOKEN}1"
M2="R${TOKEN}2"
M3="R${TOKEN}3"
MOVED=0

cleanup() {
    if [ "$MOVED" = "1" ] && [ -e "$REAL_ENGINE" ]; then
        rm -f /app/query_engine
        mv "$REAL_ENGINE" /app/query_engine
        chmod 755 /app/query_engine
        MOVED=0
    fi
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

SETUP_OK=1
if [ ! -x /app/query_engine ]; then
    SETUP_OK=0
elif ! mv /app/query_engine "$REAL_ENGINE"; then
    SETUP_OK=0
else
    MOVED=1
    chmod 755 "$REAL_ENGINE"
    : > "$LOG_FILE"
    chmod 666 "$LOG_FILE"
    cat > /app/query_engine <<EOF
#!/bin/bash
query="\$(cat)"
printf '%s\\n' "\$query" >> '$LOG_FILE'
out="\$(printf '%s\\n' "\$query" | '$REAL_ENGINE')"
status=\$?
if [ \$status -eq 0 ]; then
    case "\$query" in
        *"FROM '$N1'"*) out='$M1' ;;
        *"FROM '$N2'"*) out='$M2' ;;
        *"FROM '$N3'"*) out='$M3' ;;
    esac
fi
printf '%s\\n' "\$out"
exit \$status
EOF
    chmod 755 /app/query_engine || SETUP_OK=0
fi

export VERIFIER_REAL_ENGINE="$REAL_ENGINE"
export VERIFIER_CALL_LOG="$LOG_FILE"
export VERIFIER_PROBES="$N1:3:$M1,$N2:4:$M2,$N3:5:$M3"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import subprocess
import tempfile
import time
import pytest

HOST = "127.0.0.1"
PORT = 9090
CALL_LOG = os.environ["VERIFIER_CALL_LOG"]
PROBES = [tuple(item.split(":")) for item in os.environ["VERIFIER_PROBES"].split(",")]


def send_request_and_get_response(request_str):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect((HOST, PORT))
            s.sendall(request_str.encode("utf-8"))
            response = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
                if b"\n" in chunk:
                    break
            return response.decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with the server at {HOST}:{PORT}: {e}")


def parse_array(resp):
    assert resp.strip() != "", "Received empty response from server."
    assert resp.endswith("\n"), "Response must be terminated by a newline."
    try:
        parsed_resp = json.loads(resp)
    except json.JSONDecodeError as e:
        pytest.fail(f"Response is not valid JSON: {resp.strip()} (Error: {e})")
    assert isinstance(parsed_resp, list), f"Expected a JSON array, got {type(parsed_resp)}"
    return parsed_resp


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            if local.upper() == "0100007F:2382" and state == "0A":
                inodes.add(inode)
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except OSError:
            continue
    return pids


def clear_call_log():
    with open(CALL_LOG, "w", encoding="utf-8"):
        pass


def assert_engine_received(query):
    with open(CALL_LOG, "r", encoding="utf-8") as f:
        calls = [line.rstrip("\n") for line in f]
    assert query in calls, f"The service did not invoke /app/query_engine with {query!r}"


def oracle_result(query):
    env = os.environ.copy()
    env["GRAPH_CSV_PATH"] = "/home/user/data/edges.csv"
    proc = subprocess.run(
        ["/app/query_engine"], input=query + "\n", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=5
    )
    assert proc.returncode == 0, f"Oracle invocation failed: {proc.stderr}"
    return proc.stdout.splitlines()


def test_required_c_artifacts_and_running_program():
    source = "/home/user/server.c"
    binary = "/home/user/server"
    assert os.path.isfile(source), "/home/user/server.c is missing"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "/home/user/server is missing or not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/server is not a compiled ELF program"
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "server")
        proc = subprocess.run(
            ["gcc", "-O2", source, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert proc.returncode == 0, f"/home/user/server.c does not compile as C:\n{proc.stderr}"
    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:9090"
    assert any(os.path.samefile(f"/proc/{pid}/exe", binary) for pid in pids), \
        "The listener on 127.0.0.1:9090 is not /home/user/server"


def test_server_response_A_2():
    clear_call_log()
    req = '{"start_node": "A", "max_hops": 2}\n'
    resp = send_request_and_get_response(req)
    parsed_resp = parse_array(resp)
    assert set(parsed_resp) == {"B", "C", "D", "X"}, f"Expected nodes {{'B', 'C', 'D', 'X'}}, got {set(parsed_resp)}"
    assert_engine_received("MATCH PATH FROM 'A' MAX_HOPS 2")


def test_server_response_B_1():
    clear_call_log()
    req = '{"start_node": "B", "max_hops": 1}\n'
    resp = send_request_and_get_response(req)
    parsed_resp = parse_array(resp)
    assert set(parsed_resp) == {"C"}, f"Expected nodes {{'C'}}, got {set(parsed_resp)}"
    assert_engine_received("MATCH PATH FROM 'B' MAX_HOPS 1")


@pytest.mark.parametrize("node,hops,marker", PROBES)
def test_dynamic_engine_integration(node, hops, marker):
    query = f"MATCH PATH FROM '{node}' MAX_HOPS {int(hops)}"
    expected = oracle_result(query)
    assert expected == [marker]
    clear_call_log()
    req = json.dumps({"start_node": node, "max_hops": int(hops)}, separators=(",", ":")) + "\n"
    parsed_resp = parse_array(send_request_and_get_response(req))
    assert parsed_resp == expected, f"Expected engine-derived result {expected}, got {parsed_resp}"
    assert_engine_received(query)
TEST_EOF

if [ "$SETUP_OK" = "1" ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    REWARD=1
fi

cleanup
echo "$REWARD" > /logs/verifier/reward.txt
exit 0
