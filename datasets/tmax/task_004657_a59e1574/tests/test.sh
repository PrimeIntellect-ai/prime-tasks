#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import string
import subprocess
import tempfile

BASE_DIR = "/home/user/release_prep"

ORIGINAL_MAKEFILE = """CC=gcc
CFLAGS=-Wall

all: check_util

check_util: check_util.o
\t$(CC) $(CFLAGS) -o check_util check_util.o

check_util.o: check_util.c
\t$(CC) $(CFLAGS) -c check_util.c

clean:
\trm -f check_util check_util.o
"""

ORIGINAL_C = """#include <stdio.h>
#include <math.h>

int main() {
    double val = sqrt(16.0);
    printf(\"Validation complete. Status: %.1f\\n\", val);
    return 0;
}
"""


def test_release_env_content():
    env_file = os.path.join(BASE_DIR, "release.env")
    assert os.path.isfile(env_file), f"{env_file} does not exist."

    with open(env_file, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "SERVICE_NAME=deployment-orchestrator",
        "ENVIRONMENT=production",
        "RELEASE_VERSION=v1.4.2"
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    for expected in expected_lines:
        assert expected in actual_lines, f"Expected '{expected}' not found in {env_file}"


TOKEN_RE = re.compile(
    r'(?P<WS>\s+)|(?P<LINE>//[^\n]*)|(?P<BLOCK>/\*.*?\*/)|'
    r'(?P<STRING>"(?:[^"\\]|\\.)*")|(?P<ID>[A-Za-z_][A-Za-z0-9_]*)|'
    r'(?P<NUMBER>[0-9]+)|(?P<PUNCT>[={}();.\[\],])|(?P<BAD>.)',
    re.DOTALL,
)


def proto_tokens(text):
    result = []
    for match in TOKEN_RE.finditer(text):
        kind, value = match.lastgroup, match.group()
        if kind in ("WS", "LINE", "BLOCK"):
            continue
        assert kind != "BAD", f"Invalid protobuf token: {value!r}"
        result.append(value)
    return result


class ProtoParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0
        self.messages = {}
        self.services = {}

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def take(self, expected=None):
        assert self.pos < len(self.tokens), "Unexpected end of protobuf file"
        value = self.tokens[self.pos]
        if expected is not None:
            assert value == expected, f"Expected {expected!r}, found {value!r}"
        self.pos += 1
        return value

    def identifier(self):
        value = self.take()
        assert re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value), f"Expected identifier, found {value!r}"
        return value

    def dotted_name(self):
        parts = []
        if self.peek() == ".":
            parts.append(self.take())
        parts.append(self.identifier())
        while self.peek() == ".":
            parts.extend([self.take(), self.identifier()])
        return "".join(parts)

    def skip_field_options(self):
        if self.peek() != "[":
            return
        depth = 0
        while True:
            token = self.take()
            if token == "[":
                depth += 1
            elif token == "]":
                depth -= 1
                if depth == 0:
                    return

    def parse_message(self):
        self.take("message")
        name = self.identifier()
        assert name not in self.messages, f"Duplicate message {name}"
        self.take("{")
        fields = []
        while self.peek() != "}":
            qualifier = None
            if self.peek() in ("optional", "repeated", "required"):
                qualifier = self.take()
            field_type = self.dotted_name()
            field_name = self.identifier()
            self.take("=")
            tag = self.take()
            assert re.fullmatch(r'[0-9]+', tag), f"Invalid field tag {tag!r}"
            self.skip_field_options()
            self.take(";")
            fields.append((qualifier, field_type, field_name, int(tag)))
        self.take("}")
        self.messages[name] = fields

    def parse_service(self):
        self.take("service")
        name = self.identifier()
        assert name not in self.services, f"Duplicate service {name}"
        self.take("{")
        methods = []
        while self.peek() != "}":
            self.take("rpc")
            method = self.identifier()
            self.take("(")
            request = self.dotted_name()
            self.take(")")
            self.take("returns")
            self.take("(")
            response = self.dotted_name()
            self.take(")")
            self.take(";")
            methods.append((method, request, response))
        self.take("}")
        self.services[name] = methods

    def parse(self):
        while self.peek() is not None:
            keyword = self.peek()
            if keyword == "syntax":
                self.take("syntax")
                self.take("=")
                value = self.take()
                assert value in ('"proto2"', '"proto3"'), "Invalid protobuf syntax declaration"
                self.take(";")
            elif keyword == "package":
                self.take("package")
                self.dotted_name()
                self.take(";")
            elif keyword == "import":
                self.take("import")
                if self.peek() in ("weak", "public"):
                    self.take()
                value = self.take()
                assert value.startswith('"') and value.endswith('"'), "Invalid import path"
                self.take(";")
            elif keyword == "message":
                self.parse_message()
            elif keyword == "service":
                self.parse_service()
            else:
                raise AssertionError(f"Unexpected top-level protobuf token {keyword!r}")
        return self


def test_service_proto_updated():
    proto_file = os.path.join(BASE_DIR, "service.proto")
    assert os.path.isfile(proto_file), f"{proto_file} does not exist."
    with open(proto_file, "r") as f:
        content = f.read()

    stripped_content = re.sub(r'\s+', '', content)
    assert "messageHealthCheckResponse{" in stripped_content, "HealthCheckResponse message is missing or incorrectly formatted."
    assert "boolhealthy=1;" in stripped_content, "Field 'bool healthy = 1;' is missing in HealthCheckResponse."
    assert "rpcHealthCheck(google.protobuf.Empty)returns(HealthCheckResponse);" in stripped_content, "rpc HealthCheck definition is missing or incorrect."

    parsed = ProtoParser(proto_tokens(content)).parse()
    assert "HealthCheckResponse" in parsed.messages, "HealthCheckResponse must be a protobuf message."
    assert parsed.messages["HealthCheckResponse"] == [(None, "bool", "healthy", 1)], \
        "HealthCheckResponse must contain exactly the single field 'bool healthy = 1;'."
    assert "DeploymentService" in parsed.services, "DeploymentService service is missing."
    assert ("HealthCheck", "google.protobuf.Empty", "HealthCheckResponse") in parsed.services["DeploymentService"], \
        "HealthCheck RPC must be declared inside DeploymentService."


def run_checked(args, cwd):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=30)


def test_makefile_and_executable():
    makefile_orig = os.path.join(BASE_DIR, "Makefile.orig")
    makefile = os.path.join(BASE_DIR, "Makefile")
    source = os.path.join(BASE_DIR, "check_util.c")
    executable = os.path.join(BASE_DIR, "check_util")

    assert os.path.isfile(makefile_orig), f"Backup file {makefile_orig} does not exist."
    assert os.path.isfile(makefile), f"Makefile {makefile} does not exist."
    assert os.path.isfile(source), f"Source file {source} does not exist."

    with open(makefile_orig, "r") as f:
        assert f.read() == ORIGINAL_MAKEFILE, "Makefile.orig is not an unchanged backup of the original Makefile."
    with open(source, "r") as f:
        assert f.read() == ORIGINAL_C, "check_util.c was altered instead of fixing the Makefile."
    with open(makefile, "r") as f:
        makefile_content = f.read()
    assert "-lm" in makefile_content, "Makefile does not link the math library (-lm)."

    cleaned = run_checked(["make", "clean"], BASE_DIR)
    assert cleaned.returncode == 0, f"make clean failed:\n{cleaned.stdout}\n{cleaned.stderr}"
    assert not os.path.exists(executable), "make clean did not remove check_util."
    assert not os.path.exists(os.path.join(BASE_DIR, "check_util.o")), "make clean did not remove check_util.o."

    built = run_checked(["make"], BASE_DIR)
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(executable), f"Executable {executable} does not exist. Did you run make?"
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "check_util must be a compiled ELF executable, not a script."
    obj = os.path.join(BASE_DIR, "check_util.o")
    assert os.path.isfile(obj), "The Makefile did not compile check_util.c into check_util.o."
    with open(obj, "rb") as f:
        assert f.read(4) == b"\x7fELF", "check_util.o is not a compiled object file."

    result = subprocess.run([executable], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running {executable} failed."
    assert "Validation complete. Status: 4.0" in result.stdout, f"Unexpected output from {executable}: {result.stdout}"

    # Exercise the submitted Makefile with unpredictable source. This ensures it
    # really compiles check_util.c and links sqrt through the math library.
    token = "BUILD_" + "".join(random.choice(string.ascii_letters) for _ in range(20))
    with tempfile.TemporaryDirectory() as td:
        shutil.copy2(makefile, os.path.join(td, "Makefile"))
        generated_source = f'''#include <stdio.h>\n#include <math.h>\nint main(void) {{ volatile double x = 16.0; printf("{token} %.1f\\n", sqrt(x)); return 0; }}\n'''
        with open(os.path.join(td, "check_util.c"), "w") as f:
            f.write(generated_source)
        clean2 = run_checked(["make", "clean"], td)
        assert clean2.returncode == 0, f"Submitted Makefile's clean target failed in a fresh tree: {clean2.stderr}"
        build2 = run_checked(["make"], td)
        assert build2.returncode == 0, f"Submitted Makefile cannot compile and link check_util.c with libm:\n{build2.stdout}\n{build2.stderr}"
        test_exe = os.path.join(td, "check_util")
        assert os.path.isfile(test_exe), "Submitted Makefile did not create check_util in a fresh tree."
        with open(test_exe, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Freshly built check_util is not an ELF executable."
        probe = subprocess.run([test_exe], capture_output=True, text=True, timeout=10)
        assert probe.returncode == 0
        assert probe.stdout.strip() == f"{token} 4.0", "Built executable did not come from the supplied check_util.c."


def apply_unified_patch(original, patch_text):
    lines = patch_text.splitlines(keepends=True)
    assert len(lines) >= 3, "Patch is incomplete."
    assert re.match(r'^---\s+Makefile\.orig(?:\s|$)', lines[0]), "Patch is missing the Makefile.orig header."
    assert re.match(r'^\+\+\+\s+Makefile(?:\s|$)', lines[1]), "Patch is missing the Makefile header."

    source = original.splitlines(keepends=True)
    output = []
    source_pos = 0
    i = 2
    saw_hunk = False
    header_re = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
    while i < len(lines):
        match = header_re.match(lines[i])
        assert match, f"Invalid unified diff line: {lines[i]!r}"
        saw_hunk = True
        old_start = int(match.group(1))
        old_count = int(match.group(2) or 1)
        new_count = int(match.group(4) or 1)
        target_pos = old_start - 1
        assert target_pos >= source_pos, "Overlapping or out-of-order patch hunks."
        output.extend(source[source_pos:target_pos])
        source_pos = target_pos
        consumed = produced = 0
        i += 1
        while i < len(lines) and not lines[i].startswith("@@ "):
            line = lines[i]
            if line.startswith("\\ No newline at end of file"):
                i += 1
                continue
            assert line and line[0] in " +-", f"Invalid patch hunk line: {line!r}"
            payload = line[1:]
            if line[0] == " ":
                assert source_pos < len(source) and source[source_pos] == payload, "Patch context does not match Makefile.orig."
                output.append(payload)
                source_pos += 1
                consumed += 1
                produced += 1
            elif line[0] == "-":
                assert source_pos < len(source) and source[source_pos] == payload, "Patch deletion does not match Makefile.orig."
                source_pos += 1
                consumed += 1
            else:
                output.append(payload)
                produced += 1
            i += 1
        assert consumed == old_count, "Patch hunk has an incorrect original line count."
        assert produced == new_count, "Patch hunk has an incorrect new line count."
    assert saw_hunk, "Patch contains no hunks."
    output.extend(source[source_pos:])
    return "".join(output)


def test_makefile_patch():
    patch_file = os.path.join(BASE_DIR, "makefile_fix.patch")
    assert os.path.isfile(patch_file), f"Patch file {patch_file} does not exist."
    with open(patch_file, "r") as f:
        content = f.read()

    assert re.search(r'^---\s+Makefile\.orig', content, re.MULTILINE), f"{patch_file} does not look like a valid unified diff (missing '--- Makefile.orig')."
    assert re.search(r'^\+\+\+\s+Makefile', content, re.MULTILINE), f"{patch_file} does not look like a valid unified diff (missing '+++ Makefile')."
    assert re.search(r'^@@\s+', content, re.MULTILINE), f"{patch_file} does not contain diff hunks (missing '@@')."

    with open(os.path.join(BASE_DIR, "Makefile.orig"), "r") as f:
        original = f.read()
    with open(os.path.join(BASE_DIR, "Makefile"), "r") as f:
        fixed = f.read()
    assert fixed != original, "Makefile was not changed."
    assert apply_unified_patch(original, content) == fixed, \
        "makefile_fix.patch does not accurately transform Makefile.orig into Makefile."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
