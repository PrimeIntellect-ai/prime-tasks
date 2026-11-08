#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile

WORKSPACE = "/home/user/workspace"
SYS_PARSER = os.path.join(WORKSPACE, "sys_parser")
SYS_PARSER_ARM = os.path.join(WORKSPACE, "sys_parser_arm")
SOURCE_BUILD = "/tmp/sys_parser_source_build"


def run_checked(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=60, **kwargs)


def test_source_files_exist():
    """Verify that all required source files exist."""
    required_files = [
        os.path.join(WORKSPACE, "parser.cpp"),
        os.path.join(WORKSPACE, "action_x86.s"),
        os.path.join(WORKSPACE, "action_arm.cpp"),
        os.path.join(WORKSPACE, "Makefile"),
    ]
    for path in required_files:
        assert os.path.isfile(path), f"Required source file {path} does not exist."


def test_assembly_file_contents():
    """Verify that the assembly file has basic assembly directives."""
    asm_file = os.path.join(WORKSPACE, "action_x86.s")
    assert os.path.isfile(asm_file), f"{asm_file} does not exist."
    with open(asm_file, "r") as f:
        content = f.read()
    assert ".global process_action" in content or ".globl process_action" in content, \
        "Assembly file does not contain expected global directive for process_action."


def test_build_targets_from_sources():
    # Remove stale outputs and force both requested targets to be rebuilt.
    for path in (SYS_PARSER, SYS_PARSER_ARM):
        if os.path.lexists(path):
            os.remove(path)
    run_checked(["make", "-B", "x86"], cwd=WORKSPACE)
    run_checked(["make", "-B", "arm"], cwd=WORKSPACE)

    # Independently compile the required x86 source pair so the tested behavior
    # cannot come from an unrelated prebuilt executable emitted by the Makefile.
    run_checked([
        "g++", "-std=c++17",
        os.path.join(WORKSPACE, "parser.cpp"),
        os.path.join(WORKSPACE, "action_x86.s"),
        "-o", SOURCE_BUILD,
    ])


def test_binaries_exist_and_architecture():
    """Verify that both binaries exist and are compiled for the correct architectures."""
    assert os.path.isfile(SYS_PARSER), f"Binary {SYS_PARSER} does not exist."
    assert os.path.isfile(SYS_PARSER_ARM), f"Binary {SYS_PARSER_ARM} does not exist."

    out_x86 = subprocess.check_output(["file", SYS_PARSER]).decode("utf-8")
    assert "x86-64" in out_x86 or "x86_64" in out_x86, \
        f"{SYS_PARSER} is not an x86-64 executable."

    out_arm = subprocess.check_output(["file", SYS_PARSER_ARM]).decode("utf-8")
    assert "aarch64" in out_arm or "ARM aarch64" in out_arm, \
        f"{SYS_PARSER_ARM} is not an ARM aarch64 executable."


def test_parser_output():
    """Verify the output file and execute the produced parser on the supplied input."""
    output_file = "/home/user/parser_output.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."
    expected_output = "init:436\nstart:558\nexecute:755\n"
    with open(output_file, "r") as f:
        content = f.read()
    assert content.strip() == expected_output.strip(), \
        f"Output file content is incorrect. Got:\n{content}"

    completed = run_checked([SYS_PARSER, "/home/user/input.txt"])
    actual = completed.stdout.decode("utf-8")
    assert actual == expected_output, f"Produced parser returned incorrect output:\n{actual}"


def expected_output(actions):
    return "".join(f"{action}:{sum(map(ord, action))}\n" for action in actions)


def random_action(rng):
    alphabet = string.ascii_letters
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 24)))


def test_parsers_on_additional_dynamic_inputs():
    rng = random.SystemRandom()
    for _ in range(6):
        actions = [random_action(rng) for _ in range(5)]
        noise = "".join(rng.choice(string.ascii_letters + string.digits + " .,!?") for _ in range(30))
        stream = (
            noise
            + f"[CMD: {actions[0]}]"
            + f"[CMD:{actions[0]}]"             # missing required space
            + f"[CMD: {actions[0]}1]"           # digit makes the action invalid
            + f"[cmd: {actions[0]}]"            # wrong command case
            + f"[CMD: [CMD: {actions[1]}]"      # recover from a partial match
            + f"[CMD : {actions[0]}]"
            + f"[CMD:  {actions[0]}]"
            + f"[CMD: {actions[2]}][CMD: {actions[3]}]"
            + f"[CMD: unfinished[CMD: {actions[4]}]"  # recover at a new '['
            + "[CMD: ] [CMD: unterminated"
        )
        expected = expected_output(actions)
        with tempfile.NamedTemporaryFile(mode="wb", delete=False) as f:
            f.write(stream.encode("ascii"))
            input_path = f.name
        try:
            for executable in (SYS_PARSER, SOURCE_BUILD):
                completed = run_checked([executable, input_path])
                actual = completed.stdout.decode("utf-8")
                assert actual == expected, (
                    f"{executable} parsed a generated protocol stream incorrectly.\n"
                    f"Expected:\n{expected}Got:\n{actual}"
                )
        finally:
            os.unlink(input_path)


def build_action_harness(source, output):
    harness = output + ".cpp"
    with open(harness, "w") as f:
        f.write(r'''#include <cstring>
#include <iostream>
extern "C" int process_action(const char*, int);
int main(int argc, char** argv) {
    for (int i = 1; i < argc; ++i)
        std::cout << process_action(argv[i], static_cast<int>(std::strlen(argv[i]))) << "\n";
    return 0;
}
''')
    run_checked(["g++", "-std=c++17", harness, source, "-o", output])


def test_both_process_action_implementations():
    rng = random.SystemRandom()
    values = ["", "a", "AZaz", "execute"] + [random_action(rng) for _ in range(8)]
    expected = "".join(f"{sum(map(ord, value))}\n" for value in values)

    implementations = [
        (os.path.join(WORKSPACE, "action_x86.s"), "/tmp/test_action_x86"),
        (os.path.join(WORKSPACE, "action_arm.cpp"), "/tmp/test_action_fallback"),
    ]
    for source, output in implementations:
        build_action_harness(source, output)
        completed = run_checked([output] + values)
        actual = completed.stdout.decode("utf-8")
        assert actual == expected, f"process_action in {source} returned incorrect sums."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
