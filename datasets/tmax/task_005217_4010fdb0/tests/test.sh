#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shutil
import secrets
import subprocess
import random


def test_c_program_exists():
    """Test that the C program source and compiled executable exist."""
    assert os.path.exists("/home/user/transform.c"), "The source file /home/user/transform.c does not exist."
    assert os.path.exists("/home/user/transform"), "The compiled executable /home/user/transform does not exist."

    st = os.stat("/home/user/transform")
    assert bool(st.st_mode & stat.S_IXUSR), "The file /home/user/transform is not executable."
    with open("/home/user/transform", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/transform must be a compiled executable."


def test_bash_script_exists():
    """Test that the bash script exists and is executable."""
    assert os.path.exists("/home/user/pipeline.sh"), "The bash script /home/user/pipeline.sh does not exist."
    st = os.stat("/home/user/pipeline.sh")
    assert bool(st.st_mode & stat.S_IXUSR), "The bash script /home/user/pipeline.sh is not executable."


def test_output_csv_content():
    """Test that the output.csv file has the correct final content."""
    assert os.path.exists("/home/user/output.csv"), "The output file /home/user/output.csv does not exist."

    expected_content = """id,name,email,ssn,country
1,John Doe,john@example.com,XXX-XX-6789,US
3,Bob Smith,bob@example.com,XXX-XX-8901,UK
7,Odd Guy,odd@example.com,XXX-XX-2345,US
9,Charlie,charlie@test.com,XXX-XX-3333,FR
"""
    with open("/home/user/output.csv", "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), "The content of /home/user/output.csv does not match the expected final data. Check your C program logic and pipeline deduplication/sorting."


def expected_transform(rows):
    result = []
    for row in rows:
        fields = row.split(",")
        if int(fields[0]) % 2 == 0:
            continue
        fields[2] = fields[2].lower()
        fields[3] = "XXX-XX-" + fields[3].split("-")[2]
        result.append(",".join(fields))
    return "\n".join(result) + ("\n" if result else "")


def test_transform_executable_and_source_behaviour():
    token = secrets.token_hex(6)
    rows = [
        f"17,Alpha User,{token.upper()}@EXAMPLE.COM,123-45-6789,US",
        f"28,Even User,EVEN-{token}@EXAMPLE.COM,234-56-7890,CA",
        f"301,Final User,MiXeD-{token}@TeSt.Org,987-65-4321,GB",
        f"0,Zero User,ZERO-{token}@EXAMPLE.COM,111-22-3333,DE",
    ]
    payload = ("\n".join(rows) + "\n").encode()
    expected = expected_transform(rows)

    run = subprocess.run(
        ["/home/user/transform"], input=payload, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10, cwd="/home/user"
    )
    assert run.returncode == 0, run.stderr.decode(errors="replace")
    assert run.stdout.decode() == expected, "The compiled transform executable failed a generated input."

    rebuilt = "/tmp/verifier-rebuilt-transform"
    compile_run = subprocess.run(
        ["gcc", "/home/user/transform.c", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compile_run.returncode == 0, "transform.c does not compile:\n" + compile_run.stderr.decode(errors="replace")
    run = subprocess.run(
        [rebuilt], input=payload, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert run.returncode == 0, run.stderr.decode(errors="replace")
    assert run.stdout.decode() == expected, "The program built from transform.c failed a generated input."


def test_pipeline_on_generated_input_and_parallel_transform_calls():
    input_path = "/home/user/input.csv"
    output_path = "/home/user/output.csv"
    transform_path = "/home/user/transform"
    real_transform = "/tmp/verifier-transform-real"
    state_path = "/tmp/verifier-transform-state"
    lock_path = "/tmp/verifier-transform-lock"

    with open(input_path, "rb") as f:
        saved_input = f.read()
    saved_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            saved_output = f.read()

    shutil.copy2(transform_path, real_transform)
    token = secrets.token_hex(8)
    ids = list(range(1, 49))
    random.SystemRandom().shuffle(ids)
    rows = []
    for i in ids:
        group = i % 9
        local = f"group{group}-{token}@example.test"
        email = local.upper() if i % 3 == 0 else local.swapcase()
        ssn = f"{100 + i:03d}-{10 + (i % 80):02d}-{4000 + i:04d}"
        country = ["US", "CA", "GB", "FR"][i % 4]
        rows.append([str(i), f"Generated User {i}", email, ssn, country])

    kept = {}
    for row in rows:
        ident = int(row[0])
        if ident % 2 == 0:
            continue
        normalized = row[2].lower()
        transformed = list(row)
        transformed[2] = normalized
        transformed[3] = "XXX-XX-" + row[3].split("-")[2]
        if normalized not in kept or ident < int(kept[normalized][0]):
            kept[normalized] = transformed
    expected_rows = sorted(kept.values(), key=lambda r: int(r[0]))
    expected = "id,name,email,ssn,country\n" + "".join(",".join(r) + "\n" for r in expected_rows)

    wrapper = f'''#!/usr/bin/env python3
import fcntl
import os
import subprocess
import sys
import time
state = {state_path!r}
lock = {lock_path!r}
real = {real_transform!r}
def update(delta, add_call=False):
    with open(lock, "a+") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            with open(state, "r") as sf:
                active, calls, maximum = map(int, sf.read().split())
        except Exception:
            active, calls, maximum = 0, 0, 0
        active += delta
        if add_call:
            calls += 1
        maximum = max(maximum, active)
        with open(state, "w") as sf:
            sf.write(f"{{active}} {{calls}} {{maximum}}")
        fcntl.flock(lf, fcntl.LOCK_UN)
update(1, True)
try:
    time.sleep(0.35)
    result = subprocess.run([real] + sys.argv[1:], stdin=sys.stdin.buffer, stdout=sys.stdout.buffer, stderr=sys.stderr.buffer)
    code = result.returncode
finally:
    update(-1)
sys.exit(code)
'''

    try:
        with open(input_path, "w") as f:
            f.write("id,name,email,ssn,country\n")
            for row in rows:
                f.write(",".join(row) + "\n")
        with open(state_path, "w") as f:
            f.write("0 0 0")
        open(lock_path, "a").close()
        os.chmod(state_path, 0o666)
        os.chmod(lock_path, 0o666)
        with open(transform_path, "w") as f:
            f.write(wrapper)
        os.chmod(transform_path, 0o755)

        run = subprocess.run(
            ["/home/user/pipeline.sh"], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert run.returncode == 0, "pipeline.sh failed:\n" + run.stderr.decode(errors="replace")
        assert os.path.exists(output_path), "pipeline.sh did not generate /home/user/output.csv."
        with open(output_path, "r") as f:
            actual = f.read()
        assert actual == expected, "pipeline.sh failed generated transformation, deduplication, or numeric sorting checks."

        with open(state_path, "r") as f:
            active, calls, maximum = map(int, f.read().split())
        assert calls >= 2, "pipeline.sh did not process multiple chunks through ./transform."
        assert maximum >= 2, "pipeline.sh did not run transform chunk processing in parallel."
    finally:
        with open(input_path, "wb") as f:
            f.write(saved_input)
        if saved_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(saved_output)
        shutil.copy2(real_transform, transform_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
