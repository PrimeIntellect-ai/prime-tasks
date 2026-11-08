#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import subprocess
import tempfile
import time

WORKSPACE = "/home/user/workspace"
SOURCE = os.path.join(WORKSPACE, "manifest_parser.c")
SERVER = os.path.join(WORKSPACE, "parser_server")
EDGE = os.path.join(WORKSPACE, "parser_edge")


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Expected executable {path} is missing"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF binary"


def make_dry_run(target):
    res = run(["make", "-Bn", target], cwd=WORKSPACE, capture_output=True, text=True)
    assert res.returncode == 0, f"make -n {target} failed: {res.stderr}"
    lines = [line for line in res.stdout.splitlines() if "manifest_parser.c" in line]
    assert lines, f"{target} has no recipe compiling manifest_parser.c"
    return "\n".join(lines)


def test_files_and_implementation_structure():
    for name in ("manifest_parser.c", "Makefile", "benchmark.sh"):
        path = os.path.join(WORKSPACE, name)
        assert os.path.isfile(path), f"Expected file {path} is missing."

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = strip_c_comments(f.read())

    assert re.search(r"\benum\b", source), "Parser must define state-machine states with an enum"
    assert re.search(r"\bswitch\s*\(", source), "Parser must dispatch its byte-by-byte state machine with switch"
    assert re.search(r"\b(SERVER_MODE)\b", source), "manifest_parser.c does not handle SERVER_MODE"
    assert re.search(r"\b(EDGE_MODE)\b", source), "manifest_parser.c does not handle EDGE_MODE"

    forbidden = (
        "malloc", "calloc", "realloc", "free", "strdup", "strndup", "asprintf",
        "vasprintf", "getline", "getdelim", "strtok", "strtok_r", "sscanf",
        "fscanf", "scanf", "regcomp", "regexec"
    )
    for function in forbidden:
        assert not re.search(r"\b" + re.escape(function) + r"\s*\(", source), \
            f"Zero-allocation state-machine parser may not call {function}()"


def test_makefile_and_real_compilation():
    server_recipe = make_dry_run("server")
    edge_recipe = make_dry_run("edge")
    assert "-DSERVER_MODE" in server_recipe, "server target does not compile with -DSERVER_MODE"
    assert "-O3" in server_recipe, "server target does not compile with -O3"
    assert re.search(r"(?:^|\s)-o\s+(?:\./)?parser_server(?:\s|$)", server_recipe), \
        "server target does not compile parser_server"
    assert "-DEDGE_MODE" in edge_recipe, "edge target does not compile with -DEDGE_MODE"
    assert "-Os" in edge_recipe, "edge target does not compile with -Os"
    assert re.search(r"(?:^|\s)-o\s+(?:\./)?parser_edge(?:\s|$)", edge_recipe), \
        "edge target does not compile parser_edge"

    run(["make", "clean"], cwd=WORKSPACE, check=False)
    assert not os.path.exists(SERVER), "make clean did not remove parser_server"
    assert not os.path.exists(EDGE), "make clean did not remove parser_edge"

    res = run(["make", "server"], cwd=WORKSPACE, capture_output=True, text=True)
    assert res.returncode == 0, f"make server failed: {res.stderr}"
    assert_elf_executable(SERVER)

    res = run(["make", "edge"], cwd=WORKSPACE, capture_output=True, text=True)
    assert res.returncode == 0, f"make edge failed: {res.stderr}"
    assert_elf_executable(EDGE)

    for binary in (SERVER, EDGE):
        nm = run(["nm", "-u", binary], capture_output=True, text=True)
        symbols = nm.stdout
        for function in ("malloc", "calloc", "realloc", "free", "getline", "getdelim", "strtok", "sscanf", "fscanf", "regcomp", "regexec"):
            assert not re.search(r"\b" + function + r"(?:@|$)", symbols, flags=re.M), \
                f"{binary} imports forbidden function {function}"


def compile_private_binaries(tmpdir):
    private_server = os.path.join(tmpdir, "server")
    private_edge = os.path.join(tmpdir, "edge")
    commands = [
        ["gcc", "-std=c11", "-O3", "-DSERVER_MODE", SOURCE, "-o", private_server],
        ["gcc", "-std=c11", "-Os", "-DEDGE_MODE", SOURCE, "-o", private_edge],
    ]
    for command in commands:
        res = run(command, capture_output=True, text=True)
        assert res.returncode == 0, f"Direct compilation of manifest_parser.c failed: {res.stderr}"
    return private_server, private_edge


def invoke(binary, content, directory, sequence):
    path = os.path.join(directory, f"case_{sequence}.manifest")
    with open(path, "wb") as f:
        f.write(content)
    return run([binary, path], capture_output=True)


def valid_line(kind, name, x, y, z):
    return f"[{kind}] {name} v{x}.{y}.{z}\n".encode("ascii")


def exercise_binary(binary, server_mode, tmpdir):
    rng = random.Random(917263)
    sequence = 0

    # Retain the original fixed valid case.
    fixed = (b"[APP] my-app-1 v1.0.0\n"
             b"[LIB] core-lib v0.9.15\n"
             b"[SYS] kernel-module v5.15.0\n")
    result = invoke(binary, fixed, tmpdir, sequence)
    sequence += 1
    assert result.returncode == 0, "Parser failed on the original valid manifest"
    expected = b"SUCCESS: Parsed 3 packages.\n" if server_mode else b""
    assert result.stdout == expected, f"Unexpected mode output: {result.stdout!r}"

    # Generate varied valid manifests, including all boundary lengths and values.
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-"
    for case_index in range(25):
        count = rng.randint(1, 35)
        lines = []
        for line_index in range(count):
            if case_index == 0 and line_index == 0:
                name = "a"
                nums = (0, 0, 0)
            elif case_index == 1 and line_index == 0:
                name = "z" * 64
                nums = (999, 999, 999)
            else:
                length = rng.randint(1, 64)
                name = "".join(rng.choice(alphabet) for _ in range(length))
                nums = tuple(rng.randint(0, 999) for _ in range(3))
            lines.append(valid_line(rng.choice(("APP", "LIB", "SYS")), name, *nums))
        content = b"".join(lines)
        result = invoke(binary, content, tmpdir, sequence)
        sequence += 1
        assert result.returncode == 0, f"Parser rejected generated valid case {case_index}"
        expected = f"SUCCESS: Parsed {count} packages.\n".encode() if server_mode else b""
        assert result.stdout == expected, f"Wrong output/count for generated valid case {case_index}"

    invalid = [
        b"[UNK] my-app-1 v1.0.0\n",                 # original invalid type
        b"[APP] my_app_1 v1.0.0\n",                # original invalid name
        b"[APP] my-app-1 v1.0\n",                  # original invalid version
        b"[AP] a v1.2.3\n", b"[APPP] a v1.2.3\n",
        b"APP] a v1.2.3\n", b"[APP a v1.2.3\n", b"[APP]a v1.2.3\n",
        b"[app] a v1.2.3\n", b"[LIB]  v1.2.3\n",
        b"[SYS] " + b"a" * 65 + b" v1.2.3\n",
        b"[APP] A v1.2.3\n", b"[APP] a.b v1.2.3\n", b"[APP] a/b v1.2.3\n",
        b"[APP] a  v1.2.3\n", b"[APP] a 1.2.3\n", b"[APP] a vv1.2.3\n",
        b"[APP] a v.2.3\n", b"[APP] a v1..3\n", b"[APP] a v1.2.\n",
        b"[APP] a v-1.2.3\n", b"[APP] a v+1.2.3\n",
        b"[APP] a v1000.2.3\n", b"[APP] a v1.1000.3\n", b"[APP] a v1.2.1000\n",
        b"[APP] a v1x.2.3\n", b"[APP] a v1,2.3\n", b"[APP] a v1.2.3 extra\n",
        b"[APP] a v1.2.3", b"[APP] a v1.2.3\r\n", b"\n",
        b" [APP] a v1.2.3\n", b"[APP] a v1.2.3\n\n",
        b"[APP] a v1.2.3\ntrailing",
        b"[APP] a\x00b v1.2.3\n", b"[APP] a v1.2.3\x00\n",
    ]
    for index, content in enumerate(invalid):
        result = invoke(binary, content, tmpdir, sequence)
        sequence += 1
        assert result.returncode == 1, f"Parser accepted invalid case {index}: {content!r}"
        if not server_mode:
            assert result.stdout == b"", "EDGE mode emitted stdout for invalid input"

    missing = run([binary, os.path.join(tmpdir, "does-not-exist")], capture_output=True)
    assert missing.returncode == 1, "Parser must return 1 when the input file cannot be opened"
    no_argument = run([binary], capture_output=True)
    assert no_argument.returncode == 1, "Parser must return 1 when no manifest argument is supplied"


def test_source_behavior_on_derived_inputs():
    with tempfile.TemporaryDirectory() as tmpdir:
        private_server, private_edge = compile_private_binaries(tmpdir)
        exercise_binary(private_server, True, tmpdir)
        exercise_binary(private_edge, False, tmpdir)

        # Keep the writer open after an invalid first byte. A parser that waits for
        # EOF instead of immediately rejecting the syntax violates the requirement.
        fifo = os.path.join(tmpdir, "manifest.fifo")
        os.mkfifo(fifo)
        proc = subprocess.Popen([private_edge, fifo], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        writer = open(fifo, "wb", buffering=0)
        try:
            writer.write(b"!")
            try:
                code = proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise AssertionError("Parser did not immediately exit after a syntax error")
            assert code == 1, "Parser did not return 1 for an immediate syntax error"
        finally:
            writer.close()


def is_valid_manifest_line(line):
    match = re.fullmatch(rb"\[(APP|LIB|SYS)\] ([a-z0-9-]{1,64}) v([0-9]+)\.([0-9]+)\.([0-9]+)\n", line)
    if not match:
        return False
    return all(0 <= int(value) <= 999 for value in match.groups()[2:])


def test_benchmark_script():
    script_path = os.path.join(WORKSPACE, "benchmark.sh")
    subprocess.run(["chmod", "+x", script_path], check=True)

    with open(script_path, "r", encoding="utf-8", errors="replace") as f:
        script = f.read()
    timed_lines = [line for line in script.splitlines() if re.search(r"(^|[;&|]\s*)time\s+", line)]
    assert any("parser_server" in line for line in timed_lines), "benchmark.sh does not time parser_server"
    assert any("parser_edge" in line for line in timed_lines), "benchmark.sh does not time parser_edge"

    for name in ("large_manifest.txt", "benchmark_results.txt", "parser_server", "parser_edge"):
        path = os.path.join(WORKSPACE, name)
        if os.path.exists(path):
            os.remove(path)

    started = time.time()
    env = os.environ.copy()
    env["TIMEFORMAT"] = "__BASH_TIMED__%R"
    result = run([script_path], cwd=WORKSPACE, capture_output=True, env=env, timeout=120)
    assert result.returncode == 0, f"benchmark.sh failed: {result.stderr.decode(errors='replace')}"

    manifest_path = os.path.join(WORKSPACE, "large_manifest.txt")
    assert os.path.isfile(manifest_path), "large_manifest.txt was not created"
    with open(manifest_path, "rb") as f:
        lines = f.readlines()
    assert len(lines) == 50000, f"large_manifest.txt expected 50000 lines, got {len(lines)}"
    assert lines and all(is_valid_manifest_line(line) for line in lines), \
        "large_manifest.txt contains a malformed package line"
    assert lines[-1].endswith(b"\n"), "large_manifest.txt does not end with a newline"

    assert_elf_executable(SERVER)
    assert_elf_executable(EDGE)
    assert os.path.getmtime(SERVER) >= started - 1 and os.path.getmtime(EDGE) >= started - 1, \
        "benchmark.sh did not build both binaries during this run"

    server_result = run([SERVER, manifest_path], capture_output=True)
    edge_result = run([EDGE, manifest_path], capture_output=True)
    assert server_result.returncode == 0, "Benchmark-built parser_server rejects the generated manifest"
    assert server_result.stdout == b"SUCCESS: Parsed 50000 packages.\n", \
        "Benchmark-built parser_server produced the wrong package count"
    assert edge_result.returncode == 0, "Benchmark-built parser_edge rejects the generated manifest"
    assert edge_result.stdout == b"", "Benchmark-built parser_edge produced stdout"

    results_path = os.path.join(WORKSPACE, "benchmark_results.txt")
    assert os.path.isfile(results_path), "benchmark_results.txt was not created"
    with open(results_path, "rb") as f:
        results = f.read()
    assert b"DONE" in results, "benchmark_results.txt does not contain 'DONE'"
    assert results.split()[-1] == b"DONE", "benchmark_results.txt was not completed by appending DONE"

    timing_evidence = result.stdout + result.stderr + results
    assert timing_evidence.count(b"__BASH_TIMED__") >= 2, \
        "benchmark.sh did not invoke the bash time keyword for both parsers"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
