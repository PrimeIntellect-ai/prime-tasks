#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_parse_elf_equivalence():
    agent_script = "/home/user/parse_elf.sh"
    oracle_script = "/tests/oracle_parse_elf.sh"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    with tempfile.TemporaryDirectory() as tmpdir:
        valid_files = []
        rel_files = []
        no_rodata_files = []

        for i in range(12):
            c_file = os.path.join(tmpdir, f"source_{i}.c")
            with open(c_file, "w") as f:
                f.write(
                    f'const char policy_data_{i}[] = "variant-{i}-secure-artifact";\n'
                    f'int helper_{i}(void) {{ return policy_data_{i}[{i % 8}]; }}\n'
                    f'int main(void) {{ return helper_{i}() == 255; }}\n'
                )

            valid_elf = os.path.join(tmpdir, f"valid_{i}.elf")
            compile_cmd = ["gcc", c_file, "-o", valid_elf]
            if i % 3 == 1:
                compile_cmd.insert(1, "-no-pie")
            elif i % 3 == 2:
                compile_cmd[1:1] = ["-fPIE", "-pie"]
            run(compile_cmd)
            valid_files.append(valid_elf)

            rel_elf = os.path.join(tmpdir, f"rel_{i}.o")
            run(["gcc", "-c", c_file, "-o", rel_elf])
            rel_files.append(rel_elf)

            no_rodata = os.path.join(tmpdir, f"no_rodata_{i}.elf")
            run(["objcopy", "--remove-section", ".rodata", valid_elf, no_rodata])
            no_rodata_files.append(no_rodata)

        categories = [category for category in range(5) for _ in range(20)]
        random.SystemRandom().shuffle(categories)
        test_files = []

        for i, category in enumerate(categories):
            test_file = os.path.join(tmpdir, f"case_{secrets.token_hex(12)}")
            variant = secrets.randbelow(len(valid_files))

            if category == 0:
                mode = i % 4
                if mode == 0:
                    open(test_file, "wb").close()
                elif mode == 1:
                    with open(test_file, "wb") as f:
                        f.write(b"#!/bin/sh\necho not-an-elf\n")
                elif mode == 2:
                    with open(valid_files[variant], "rb") as src, open(test_file, "wb") as dst:
                        dst.write(src.read(secrets.randbelow(12) + 1))
                else:
                    with open(test_file, "wb") as f:
                        f.write(os.urandom(secrets.randbelow(400) + 1))
            elif category == 1:
                shutil.copyfile(valid_files[variant], test_file)
            elif category == 2:
                shutil.copyfile(no_rodata_files[variant], test_file)
            elif category == 3:
                with open(valid_files[variant], "rb") as f:
                    data = bytearray(f.read())
                data[0x12] = 0xB7
                data[0x13] = 0x00
                with open(test_file, "wb") as f:
                    f.write(data)
            else:
                shutil.copyfile(rel_files[variant], test_file)

            test_files.append(test_file)

        expected = []
        for test_file in test_files:
            oracle_proc = subprocess.run(
                ["bash", oracle_script, test_file],
                capture_output=True,
                text=True,
            )
            expected.append(oracle_proc.stdout.strip())

        # The reference is needed only to derive hidden expectations. Remove it
        # before any submitted code is executed so the submission cannot delegate.
        os.unlink(oracle_script)

        for test_file, oracle_out in zip(test_files, expected):
            agent_proc = subprocess.run(
                ["bash", agent_script, test_file],
                capture_output=True,
                text=True,
            )
            agent_out = agent_proc.stdout.strip()

            assert agent_out == oracle_out, (
                f"Mismatch on file {test_file}.\n"
                f"Expected (Oracle): {oracle_out}\n"
                f"Got (Agent): {agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
