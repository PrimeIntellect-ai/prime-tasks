#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess

PACKAGE = "/app/librouteconf-2.1.0"
AGENT_SOURCE = "/home/user/route_canonicalizer.cpp"
AGENT_BIN = "/home/user/route_canonicalizer"
REBUILT_BIN = "/tmp/route_canonicalizer_from_source"


def run(command, **kwargs):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=15, **kwargs)


def test_makefile_fixed():
    """Keep the original check for removal of the perturbation flag."""
    makefile_path = os.path.join(PACKAGE, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile missing at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-DBROKEN_WHITESPACE_PARSING=1" not in content, (
        "The perturbation flag -DBROKEN_WHITESPACE_PARSING=1 is still present in the Makefile."
    )


def test_rebuild_source_and_linkage():
    """Rebuild the fixed library and independently compile the submitted source."""
    assert os.path.isfile(AGENT_SOURCE), f"Source missing at {AGENT_SOURCE}"
    assert os.path.getsize(AGENT_SOURCE) > 0, "Submitted source is empty"
    with open(AGENT_SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert "RouteConf::parse_and_format" in source, (
        "Submitted source does not use RouteConf::parse_and_format"
    )

    for command in (["make", "clean"], ["make"], ["make", "install"]):
        proc = run(command, cwd=PACKAGE)
        assert proc.returncode == 0, (
            f"Command {command!r} failed:\n{proc.stdout.decode(errors='replace')}"
            f"\n{proc.stderr.decode(errors='replace')}"
        )

    library = os.path.join(PACKAGE, "librouteconf.so")
    assert os.path.isfile(library), "The library was not rebuilt"
    assert os.path.isfile("/usr/local/lib/librouteconf.so"), "The fixed library was not installed"

    compile_proc = run([
        "g++", "-std=c++17", AGENT_SOURCE,
        f"-I{PACKAGE}/include", "-L/usr/local/lib",
        "-Wl,-rpath,/usr/local/lib", "-lrouteconf", "-o", REBUILT_BIN,
    ])
    assert compile_proc.returncode == 0, (
        "Submitted C++ source could not be compiled against the fixed library:\n"
        + compile_proc.stdout.decode(errors="replace")
        + compile_proc.stderr.decode(errors="replace")
    )

    for binary in (AGENT_BIN, REBUILT_BIN):
        assert os.path.isfile(binary), f"Executable missing at {binary}"
        assert os.access(binary, os.X_OK), f"{binary} is not executable"
        file_proc = run(["file", binary])
        assert file_proc.returncode == 0 and b"ELF" in file_proc.stdout, (
            f"{binary} is not an ELF executable"
        )
        dynamic = run(["readelf", "-d", binary])
        assert dynamic.returncode == 0, f"Unable to inspect linkage of {binary}"
        assert b"librouteconf.so" in dynamic.stdout, (
            f"{binary} is not dynamically linked against librouteconf.so"
        )


def test_log_router_service_starts():
    """Exercise the supplied service fixture with the rebuilt library."""
    assert os.path.isfile("/etc/systemd/system/log-router.service"), (
        "log-router.service fixture is missing"
    )
    assert os.path.isfile("/etc/init.d/log-router"), "log-router init fixture is missing"

    run(["/etc/init.d/log-router", "stop"])
    started = run(["/etc/init.d/log-router", "start"])
    assert started.returncode == 0, (
        "log-router.service failed to start with the rebuilt library:\n"
        + started.stdout.decode(errors="replace")
        + started.stderr.decode(errors="replace")
    )
    status = run(["/etc/init.d/log-router", "status"])
    assert status.returncode == 0, "log-router.service is not healthy after startup"


def expected_result(inp):
    if inp == "":
        return 1, b""

    # std::getline reads only the first configuration line.
    line = inp.split("\n", 1)[0]
    if "INVALID" in line:
        return 1, b""

    tokens = [token.strip(" \t\n\r") for token in line.split("->")]
    return 0, (" -> ".join(tokens) + "\n").encode("utf-8")


def check_input(inp):
    expected_code, expected_stdout = expected_result(inp)
    data = inp.encode("utf-8")
    for binary in (AGENT_BIN, REBUILT_BIN):
        proc = run([binary], input=data)
        assert proc.returncode == expected_code, (
            f"Exit code mismatch for {binary} on input {inp!r}: "
            f"expected {expected_code}, got {proc.returncode}"
        )
        assert proc.stdout == expected_stdout, (
            f"Stdout mismatch for {binary} on input {inp!r}: "
            f"expected {expected_stdout!r}, got {proc.stdout!r}"
        )


def test_fuzz_equivalence():
    """Preserve the fuzz check, deriving answers rather than trusting an image oracle."""
    edge_cases = [
        "", "\n", "a", "  a  ->\tb\t", " -> ", "a->->b",
        "INVALID", "a -> INVALID -> b", "a\rb", "x" * 1024,
    ]
    for inp in edge_cases:
        check_input(inp)

    random.seed(42)
    valid_chars = string.ascii_letters + string.digits + " ->:,"
    for _ in range(1000):
        length = random.randint(10, 500)
        if random.random() < 0.2:
            inp = "".join(random.choices(string.printable, k=length))
        else:
            inp = "".join(random.choices(valid_chars, k=length))
        check_input(inp)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
