#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verifier-tools
mkdir -p /tmp/verifier-tools

cat << 'EOF' > /tmp/verifier-tools/gcc
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["GCC_LOG"], "a") as f:
    f.write(json.dumps({"cwd": os.getcwd(), "args": sys.argv[1:]}) + "\n")
os.execv("/usr/bin/gcc", ["gcc"] + sys.argv[1:])
EOF

cat << 'EOF' > /tmp/verifier-tools/ar
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["AR_LOG"], "a") as f:
    f.write(json.dumps({"cwd": os.getcwd(), "args": sys.argv[1:]}) + "\n")
os.execv("/usr/bin/ar", ["ar"] + sys.argv[1:])
EOF
chmod +x /tmp/verifier-tools/gcc /tmp/verifier-tools/ar

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import math
import os
import re
import shutil
import subprocess

SCRIPT = "/home/user/build_system.sh"
BINARY = "/home/user/bin/sec_tool"
LOG = "/home/user/build_output.log"
SRC = "/home/user/src"
EXPECTED = (
    "Entropy: 3.6622\n"
    "WS: Upgrade Request\n"
    "REST: Fallback Request\n"
)


def test_build_system_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"


def test_sec_tool_executable_exists():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"


def test_build_output_log_contents():
    assert os.path.isfile(LOG), f"{LOG} does not exist"
    with open(LOG, "r") as f:
        content = f.read()
    assert "Entropy: 3.6622" in content, "Expected 'Entropy: 3.6622' in build_output.log"
    assert "WS: Upgrade Request" in content, "Expected 'WS: Upgrade Request' in build_output.log"
    assert "REST: Fallback Request" in content, "Expected 'REST: Fallback Request' in build_output.log"


def test_build_system_script_resolves_circular_dependency():
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "--start-group" in content and "--end-group" in content, (
        "The build script does not seem to use GNU linker group flags "
        "(--start-group and --end-group) to resolve circular dependencies."
    )
    assert "libws.a" in content, "libws.a not found in the build script"
    assert "librest.a" in content, "librest.a not found in the build script"


def clean_products():
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            if name.endswith((".o", ".a")) or name == "sec_tool":
                os.unlink(os.path.join(root, name))


def load_records(path):
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def resolved(cwd, path):
    return os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path))


def expected_output(payload, upgrade, fallback):
    counts = collections.Counter(payload.encode())
    n = len(payload.encode())
    entropy = -sum((v / n) * math.log2(v / n) for v in counts.values()) if n else 0.0
    return f"Entropy: {entropy:.4f}\nWS: {upgrade}\nREST: {fallback}\n"


def run_and_validate(mode, expected):
    clean_products()
    gcc_log = f"/tmp/gcc-{mode[2:]}.jsonl"
    ar_log = f"/tmp/ar-{mode[2:]}.jsonl"
    open(gcc_log, "w").close()
    open(ar_log, "w").close()
    env = os.environ.copy()
    env["PATH"] = "/tmp/verifier-tools:" + env.get("PATH", "")
    env["GCC_LOG"] = gcc_log
    env["AR_LOG"] = ar_log
    subprocess.run([SCRIPT, mode], cwd="/home/user", env=env, check=True, timeout=60)

    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    elf = subprocess.run(["readelf", "-h", BINARY], text=True, capture_output=True)
    assert elf.returncode == 0 and "ELF" in elf.stdout, "sec_tool is not an ELF executable"
    actual = subprocess.run([BINARY], text=True, capture_output=True, check=True, timeout=10)
    assert actual.stderr == ""
    assert actual.stdout == expected

    gcc_calls = load_records(gcc_log)
    ar_calls = load_records(ar_log)
    assert gcc_calls, "The build script did not invoke gcc"
    assert ar_calls, "The build script did not invoke ar"

    required_flags = ["-g", "-DDEBUG_MODE"] if mode == "--debug" else ["-O3", "-DNDEBUG"]
    for call in gcc_calls:
        for flag in required_flags:
            assert flag in call["args"], f"gcc invocation is missing {flag}: {call['args']}"

    required_sources = {os.path.realpath(os.path.join(SRC, x)) for x in ("num.c", "rest.c", "ws.c", "main.c")}
    compiled_sources = set()
    for call in gcc_calls:
        if "-c" in call["args"]:
            for arg in call["args"]:
                if arg.endswith(".c"):
                    compiled_sources.add(resolved(call["cwd"], arg))
    assert required_sources <= compiled_sources, "The script did not compile all four supplied C source files"

    archives = {}
    for call in ar_calls:
        for arg in call["args"]:
            base = os.path.basename(arg)
            if base in ("libnum.a", "librest.a", "libws.a"):
                archives[base] = resolved(call["cwd"], arg)
                break
    assert set(archives) == {"libnum.a", "librest.a", "libws.a"}, "All three static libraries were not archived"
    expected_members = {"libnum.a": "num.o", "librest.a": "rest.o", "libws.a": "ws.o"}
    for lib, path in archives.items():
        assert os.path.isfile(path), f"Missing archive {lib}"
        members = subprocess.check_output(["/usr/bin/ar", "t", path], text=True).splitlines()
        assert expected_members[lib] in [os.path.basename(x) for x in members], f"{lib} lacks its required object"

    symbols = {
        "libnum.a": "calc_entropy",
        "librest.a": "rest_upgrade",
        "libws.a": "ws_fallback",
    }
    for lib, symbol in symbols.items():
        nm = subprocess.check_output(["nm", "-g", "--defined-only", archives[lib]], text=True)
        assert re.search(rf"\b{re.escape(symbol)}$", nm, re.MULTILINE), f"{lib} does not define {symbol}"

    link_calls = []
    for call in gcc_calls:
        args = call["args"]
        if "-o" in args:
            i = args.index("-o")
            if i + 1 < len(args) and resolved(call["cwd"], args[i + 1]) == os.path.realpath(BINARY):
                link_calls.append(call)
    assert link_calls, "No gcc invocation linked /home/user/bin/sec_tool"
    args = link_calls[-1]["args"]
    starts = [i for i, x in enumerate(args) if "--start-group" in x]
    ends = [i for i, x in enumerate(args) if "--end-group" in x]
    assert starts and ends and starts[0] < ends[-1], "The executed link command lacks a valid linker group"
    group = args[starts[0] + 1:ends[-1]]
    has_rest = any(os.path.basename(x) == "librest.a" or x == "-lrest" for x in group)
    has_ws = any(os.path.basename(x) == "libws.a" or x == "-lws" for x in group)
    assert has_rest and has_ws, "librest and libws were not both inside the executed linker group"
    assert "-lm" in args, "The executed link command did not link the math library with -lm"


def test_script_really_builds_both_modes_and_uses_sources():
    main_path = os.path.join(SRC, "main.c")
    with open(main_path, "r") as f:
        original = f.read()
    try:
        variants = [
            ("--debug", "DEBUG_DYNAMIC_PAYLOAD_731", "Debug Upgrade 731", "Debug Fallback 731"),
            ("--release", "RELEASE_DYNAMIC_PAYLOAD_947", "Release Upgrade 947", "Release Fallback 947"),
        ]
        for mode, payload, upgrade, fallback in variants:
            changed = original.replace("SECURITY_PAYLOAD_TEST", payload)
            changed = changed.replace("Upgrade Request", upgrade).replace("Fallback Request", fallback)
            with open(main_path, "w") as f:
                f.write(changed)
            run_and_validate(mode, expected_output(payload, upgrade, fallback))
    finally:
        with open(main_path, "w") as f:
            f.write(original)

    # Leave the requested release build in place and verify its canonical behavior.
    run_and_validate("--release", EXPECTED)
TEST_EOF

if GCC_LOG=/tmp/unused-gcc AR_LOG=/tmp/unused-ar python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
