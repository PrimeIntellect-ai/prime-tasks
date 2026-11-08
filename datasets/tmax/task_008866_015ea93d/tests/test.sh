#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile

SRC = "/home/user/new_auth_worker.cpp"
BIN = "/home/user/new_auth_worker_fixed"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=20, **kwargs)


def sanitize_cpp(text):
    out = list(text)
    i = 0
    state = "code"
    while i < len(text):
        if state == "code":
            if text.startswith("//", i):
                out[i] = out[i + 1] = " "
                i += 2
                state = "line"
            elif text.startswith("/*", i):
                out[i] = out[i + 1] = " "
                i += 2
                state = "block"
            elif text[i] == '"':
                out[i] = " "
                i += 1
                state = "string"
            elif text[i] == "'":
                out[i] = " "
                i += 1
                state = "char"
            else:
                i += 1
        elif state == "line":
            if text[i] == "\n":
                state = "code"
            else:
                out[i] = " "
            i += 1
        elif state == "block":
            if text.startswith("*/", i):
                out[i] = out[i + 1] = " "
                i += 2
                state = "code"
            else:
                if text[i] != "\n":
                    out[i] = " "
                i += 1
        else:
            if text[i] == "\\" and i + 1 < len(text):
                if text[i] != "\n":
                    out[i] = " "
                if text[i + 1] != "\n":
                    out[i + 1] = " "
                i += 2
            elif (state == "string" and text[i] == '"') or (state == "char" and text[i] == "'"):
                out[i] = " "
                i += 1
                state = "code"
            else:
                if text[i] != "\n":
                    out[i] = " "
                i += 1
    return "".join(out)


def function_bounds(clean, pattern):
    match = re.search(pattern, clean)
    assert match, f"Required function signature matching {pattern!r} was not found."
    opening = clean.find("{", match.end())
    assert opening != -1, "Function body was not found."
    depth = 0
    for i in range(opening, len(clean)):
        if clean[i] == "{":
            depth += 1
        elif clean[i] == "}":
            depth -= 1
            if depth == 0:
                return opening, i
    raise AssertionError("Function body has unbalanced braces.")


def compile_and_probe(source_text, inputs):
    with tempfile.TemporaryDirectory() as td:
        source_path = os.path.join(td, "worker.cpp")
        object_path = os.path.join(td, "worker.o")
        harness_path = os.path.join(td, "harness.cpp")
        probe_path = os.path.join(td, "probe")
        with open(source_path, "w") as f:
            f.write(source_text)
        with open(harness_path, "w") as f:
            f.write('#include <iostream>\n#include <string>\n#include <vector>\n')
            f.write('bool check_host(const std::string&);\nint main() {\n')
            f.write('std::vector<std::string> values = {')
            f.write(",".join(json.dumps(value) for value in inputs))
            f.write('};\nfor (const auto& value : values) std::cout << (check_host(value) ? "1" : "0") << "\\n";\nreturn 0;\n}\n')
        run(["g++", "-std=c++17", "-Dmain=agent_worker_main", "-c", source_path, "-o", object_path])
        run(["g++", "-std=c++17", harness_path, object_path, "-o", probe_path])
        result = run([probe_path])
        return result.stdout.splitlines()


def test_password_extracted_correctly():
    pwd_file = "/home/user/old_password.txt"
    assert os.path.exists(pwd_file), f"File {pwd_file} does not exist."
    with open(pwd_file, "rb") as f:
        content = f.read()
    assert content == b"Str0ngL3gacyP@ssw0rd!2023\n", "The password file must contain exactly the extracted password and one trailing newline."


def test_vulnerability_fixed_in_source_and_behavior():
    assert os.path.exists(SRC), f"File {SRC} does not exist."
    with open(SRC, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "system(" not in content, "The system() call is still present in the source code."
    assert "safe_ping(" in content, "The safe_ping() function is not used in the source code."

    clean = sanitize_cpp(content)
    check_open, check_close = function_bounds(
        clean, r"\bbool\s+check_host\s*\(\s*const\s+std::string\s*&\s*host\s*\)"
    )
    check_body = clean[check_open + 1:check_close]
    assert re.search(r"\bsafe_ping\s*\(\s*host\s*\)", check_body), "check_host must call safe_ping(host)."
    assert not re.search(r"\bsystem\s*\(", clean), "A system() call remains in executable source code."

    token = "host-" + secrets.token_hex(8)
    inputs = ["127.0.0.1", "example.com", token, "", "bad;id", "bad&&id", "bad|id", "bad`id`", "bad$id"]
    expected = ["0" if any(c in value for c in ";&|`$") else "1" for value in inputs]
    assert compile_and_probe(content, inputs) == expected, "check_host does not preserve safe_ping's required success/failure behavior."

    # Replace safe_ping's implementation with a verifier-chosen oracle. This proves
    # check_host actually delegates its result instead of merely mentioning safe_ping.
    safe_open, safe_close = function_bounds(
        clean, r"\bbool\s+safe_ping\s*\(\s*const\s+std::string\s*&\s*host\s*\)"
    )
    secret_host = "probe-" + secrets.token_hex(12)
    replacement = "\n    return host == " + json.dumps(secret_host) + ";\n"
    instrumented = content[:safe_open + 1] + replacement + content[safe_close:]
    delegated_inputs = [secret_host, token, "127.0.0.1", "bad;id"]
    assert compile_and_probe(instrumented, delegated_inputs) == ["1", "0", "0", "0"], "check_host does not return the result of safe_ping(host)."


def test_fixed_binary_compiled_and_executable():
    assert os.path.exists(BIN), f"Compiled binary {BIN} does not exist."
    assert os.path.isfile(BIN), f"{BIN} is not a file."
    assert os.access(BIN, os.X_OK), f"Compiled binary {BIN} is not executable."
    with open(BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN} is not a valid ELF executable."

    symbols = run(["nm", "-C", BIN]).stdout
    assert re.search(r"\bcheck_host\(std::.*string.*\)", symbols), "The executable does not contain the compiled check_host function."
    assert re.search(r"\bsafe_ping\(std::.*string.*\)", symbols), "The executable does not contain the compiled safe_ping function."
    assert not any(re.search(r"\bU\s+system(?:@|$)", line) for line in symbols.splitlines()), "The executable still imports system()."

    result = run([BIN])
    assert result.returncode == 0, "The compiled executable failed when run."
    assert "Host is up!" in result.stdout, "The compiled executable does not exhibit the patched worker's expected behavior."


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
