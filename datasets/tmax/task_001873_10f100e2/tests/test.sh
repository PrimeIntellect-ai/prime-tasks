#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import stat
import subprocess
import time

HOST = "127.0.0.1"
PORT = 8080
SOURCE = "/home/user/graph_server.c"
LOG = "/home/user/query_log.txt"
LIBDIR = "/app/vendored/simple_csv_parser"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"


def connect_with_retries(attempts=20):
    last_error = None
    for _ in range(attempts):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        try:
            s.connect((HOST, PORT))
            return s
        except OSError as exc:
            last_error = exc
            s.close()
            time.sleep(0.25)
    raise AssertionError(f"Failed to connect to TCP server at {HOST}:{PORT}: {last_error}")


def send_query(s, query):
    s.sendall(query.encode("utf-8"))
    response = b""
    while b"\n" not in response:
        chunk = s.recv(4096)
        if not chunk:
            break
        response += chunk
    return response.decode("utf-8")


def wait_for_log(queries):
    deadline = time.time() + 3
    content = ""
    while time.time() < deadline:
        if os.path.isfile(LOG):
            with open(LOG, "r", errors="replace") as f:
                content = f.read()
            if all(q.rstrip("\n") in content for q in queries):
                return content
        time.sleep(0.1)
    return content


def listener_inodes():
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def stop_port_8080():
    for _ in range(20):
        inodes = listener_inodes()
        if not inodes:
            return
        victims = set()
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            fd_dir = f"/proc/{entry}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                    except OSError:
                        continue
                    match = re.fullmatch(r"socket:\[(\d+)\]", target)
                    if match and match.group(1) in inodes:
                        victims.add(int(entry))
                        break
            except (FileNotFoundError, PermissionError):
                continue
        for pid in victims:
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
        time.sleep(0.15)
    assert not listener_inodes(), "Could not stop the original server on port 8080"


def descendants(adjacency, node):
    seen = set()
    stack = list(adjacency.get(node, ()))
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        stack.extend(adjacency.get(current, ()))
    return sorted(seen)


def test_complete_submission():
    # Preserve the original verifier's source and fixed-dataset assertions.
    assert os.path.isfile(SOURCE), f"Source file missing: {SOURCE}"
    mode = os.stat(SOURCE, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"Source path is not a regular file: {SOURCE}"

    original_queries = [
        "GET_DESCENDANTS A\n",
        "GET_DESCENDANTS B\n",
        "GET_DESCENDANTS C\n",
        "GET_DESCENDANTS X\n",
    ]
    original_expected = ["B,C,D\n", "D\n", "NONE\n", "NONE\n"]
    s = connect_with_retries()
    try:
        for query, expected in zip(original_queries, original_expected):
            actual = send_query(s, query)
            assert actual == expected, f"Expected {expected!r} for {query!r}, got {actual!r}"
    finally:
        s.close()

    assert os.path.isfile(LOG), f"Query log missing: {LOG}"
    original_log = wait_for_log(original_queries)
    for query in original_queries:
        assert query.rstrip("\n") in original_log, f"Query log does not contain {query.rstrip()!r}"

    stop_port_8080()

    # The Makefile itself must be repaired, and the vendored library must build.
    makefile = os.path.join(LIBDIR, "Makefile")
    with open(makefile, "r", errors="replace") as f:
        make_text = f.read()
    assert "invalid_compiler" not in make_text, "The vendored library Makefile was not fixed"
    subprocess.run(["make", "clean"], cwd=LIBDIR, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    subprocess.run(["make"], cwd=LIBDIR, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    archive = os.path.join(LIBDIR, "libcsv_parser.a")
    assert os.path.isfile(archive), "Vendored static library was not produced"

    # Recompile the submitted source ourselves and require the archive's parser
    # object to actually be selected by the linker.
    verified_binary = "/tmp/verified_graph_server"
    link_map = "/tmp/verified_graph_server.map"
    subprocess.run([
        "gcc", "-std=gnu11", "-O2", SOURCE,
        "-I", LIBDIR, "-L", LIBDIR, "-lcsv_parser", "-pthread",
        f"-Wl,-Map,{link_map}", "-o", verified_binary,
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    with open(link_map, "r", errors="replace") as f:
        map_text = f.read()
    assert "libcsv_parser.a(csv_parser.o)" in map_text, "Submitted program did not actually link the vendored CSV parser object"

    # Replace the fixture with an unpredictable graph so fixed-response servers
    # cannot pass. Expected answers are derived independently from these edges.
    token = secrets.token_hex(6)
    root = "R" + token
    a = "A" + token
    b = "B" + token
    c = "C" + token
    d = "D" + token
    e = "E" + token
    isolated = "I" + token
    missing = "Z" + token
    node_ids = [root, a, b, c, d, e, isolated]
    edge_pairs = [
        (root, b), (root, a), (a, d), (b, c), (c, e), (d, e)
    ]
    adjacency = {}
    for parent, child in edge_pairs:
        adjacency.setdefault(parent, []).append(child)

    with open(NODES, "w") as f:
        f.write("id,name\n")
        for index, node in enumerate(node_ids):
            f.write(f"{node},Generated node {index}\n")
    with open(EDGES, "w") as f:
        f.write("parent_id,child_id\n")
        for parent, child in edge_pairs:
            f.write(f"{parent},{child}\n")

    proc = subprocess.Popen([verified_binary], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dynamic_queries = []
    try:
        s = connect_with_retries()
        try:
            # Exercise persistent connections, transitive closure, sorting,
            # duplicate-path deduplication, leaves, isolated nodes, and misses.
            for node in [root, a, b, c, d, e, isolated, missing, root]:
                query = f"GET_DESCENDANTS {node}\n"
                dynamic_queries.append(query)
                answer = descendants(adjacency, node)
                expected = (",".join(answer) if answer else "NONE") + "\n"
                actual = send_query(s, query)
                assert actual == expected, f"Expected {expected!r} for generated node {node!r}, got {actual!r}"
        finally:
            s.close()

        dynamic_log = wait_for_log(dynamic_queries)
        for query in dynamic_queries:
            assert query.rstrip("\n") in dynamic_log, f"Query log does not contain generated query {query.rstrip()!r}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_port_8080()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
