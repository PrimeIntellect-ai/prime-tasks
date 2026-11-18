#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
import tempfile


def test_makefile_fixed():
    makefile_path = "/app/vendored-tracker-1.2/Makefile"
    assert os.path.isfile(makefile_path), f"File {makefile_path} does not exist."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "sed -i ''" not in content, "Makefile still contains the macOS-style sed command."


def test_make_setup_run_and_created_real_elfs():
    generator = "/app/vendored-tracker-1.2/generator"
    assert os.path.isfile(generator), "The generator was not compiled by make setup."
    assert os.access(generator, os.X_OK), "The compiled generator is not executable."

    test_elfs_path = "/home/user/test_elfs"
    assert os.path.isdir(test_elfs_path), "Directory /home/user/test_elfs does not exist. Did you run make setup?"
    elfs = [
        os.path.join(test_elfs_path, f)
        for f in os.listdir(test_elfs_path)
        if f.endswith(".elf") and os.path.isfile(os.path.join(test_elfs_path, f))
    ]
    assert len(elfs) > 0, "No ELF files found in /home/user/test_elfs."
    assert len(elfs) >= 2, "make setup did not create several test ELF binaries."

    for elf in elfs:
        with open(elf, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{elf} is not an ELF binary."
        result = subprocess.run(["readelf", "-h", elf], capture_output=True, text=True)
        assert result.returncode == 0, f"readelf could not parse generated ELF {elf}: {result.stderr}"


def oracle(elf_path):
    result = subprocess.run(["readelf", "-W", "-S", elf_path], capture_output=True, text=True, check=True)
    output = []
    section_line = re.compile(
        r"^\s*\[\s*\d+\]\s+(\S+)\s+\S+\s+[0-9A-Fa-f]+\s+([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)(?:\s|$)"
    )
    for line in result.stdout.splitlines():
        match = section_line.match(line)
        if not match:
            continue
        name, offset, size = match.groups()
        if name.startswith(".cfg_"):
            size_dec = int(size, 16)
            # Preserve readelf's hexadecimal width, including leading zeroes.
            offset_hex = "0x" + offset.lower()
            output.append(f"WAL_RECORD: name={name} size={size_dec} offset={offset_hex}")
    return "\n".join(output)


def create_random_elf(path, num_sections=None):
    c_file = path + ".c"
    with open(c_file, "w") as f:
        f.write("int main(void) { return 0; }\n")
    subprocess.run(["gcc", c_file, "-o", path], check=True)

    if num_sections is None:
        num_sections = random.randint(0, 10)
    for _ in range(num_sections):
        sec_name = ".cfg_" + "".join(random.choices(string.ascii_letters + string.digits + "_", k=8))
        sec_size = random.randint(1, 65536)
        sec_file = path + ".sec"
        with open(sec_file, "wb") as f:
            f.write(os.urandom(sec_size))
        subprocess.run(["objcopy", "--add-section", f"{sec_name}={sec_file}", path], check=True)
        os.remove(sec_file)
    os.remove(c_file)


def assert_exact_output(actual, expected):
    # Preserve the original stripped equivalence assertion, then reject extra
    # blank lines or other stdout while allowing a conventional final newline.
    assert actual.strip() == expected.strip(), f"Oracle Output:\n{expected}\n\nAgent Output:\n{actual}"
    if expected:
        assert actual == expected or actual == expected + "\n", "Output contains extra whitespace or lines."
    else:
        assert actual == "", "The script must produce no output when no .cfg_ sections exist."


def test_argument_count_and_empty_result():
    agent_script = "/home/user/elf_to_wal.sh"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."

    no_arg = subprocess.run(["/bin/bash", agent_script], capture_output=True, text=True)
    assert no_arg.returncode != 0, "The script must reject zero arguments."

    with tempfile.TemporaryDirectory() as tmpdir:
        elf_path = os.path.join(tmpdir, "plain.elf")
        create_random_elf(elf_path, num_sections=0)

        two_args = subprocess.run(["/bin/bash", agent_script, elf_path, elf_path], capture_output=True, text=True)
        assert two_args.returncode != 0, "The script must reject more than one argument."

        result = subprocess.run(["/bin/bash", agent_script, elf_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Agent script failed on an ELF without cfg sections: {result.stderr}"
        assert_exact_output(result.stdout, "")


def test_fuzz_equivalence():
    agent_script = "/home/user/elf_to_wal.sh"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."

    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(25):
            elf_path = os.path.join(tmpdir, f"test_{i}.elf")
            create_random_elf(elf_path)
            oracle_out = oracle(elf_path)

            agent_res = subprocess.run(["/bin/bash", agent_script, elf_path], capture_output=True, text=True)
            assert agent_res.returncode == 0, f"Agent script failed on input with {elf_path}. Stderr: {agent_res.stderr}"
            assert_exact_output(agent_res.stdout, oracle_out)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
