#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import stat
import subprocess

import pytest

CSV_PATH = "/home/user/reviews.csv"
SOURCE_PATH = "/home/user/analyze.c"
SCRIPT_PATH = "/home/user/run_pipeline.sh"
RESULT_PATH = "/home/user/analysis_result.txt"


def expected_output(csv_path=CSV_PATH):
    five_star_count = 0
    token_lengths = []

    with open(csv_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",", 2)
            if len(parts) == 3:
                rating = parts[1]
                text = parts[2]
                if rating == "5":
                    five_star_count += 1
                    tokens = re.split(r"[ \t\n.,!?;:]+", text)
                    token_lengths.extend(len(token) for token in tokens if token)

    total_tokens = len(token_lengths)
    if total_tokens > 0:
        mean = sum(token_lengths) / total_tokens
        if total_tokens > 1:
            variance = sum((x - mean) ** 2 for x in token_lengths) / (total_tokens - 1)
            std_dev = math.sqrt(variance)
        else:
            std_dev = 0.0
        margin = 1.96 * std_dev / math.sqrt(total_tokens)
        lower = mean - margin
        upper = mean + margin
    else:
        mean = lower = upper = 0.0

    return (
        f"Total 5-star reviews: {five_star_count}\n"
        f"Total tokens in 5-star reviews: {total_tokens}\n"
        f"Mean token length: {mean:.4f}\n"
        f"95% CI: [{lower:.4f}, {upper:.4f}]"
    )


def assert_result_matches():
    assert os.path.exists(RESULT_PATH), f"The output file {RESULT_PATH} is missing."
    with open(RESULT_PATH, "r") as f:
        actual = f.read().strip()
    expected = expected_output()
    assert actual == expected, (
        f"The content of {RESULT_PATH} does not match the expected output.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def random_dataset():
    def word():
        length = 1 + secrets.randbelow(17)
        return "x" * length

    rows = [
        f"101,5,{word()}  {word()}!{word()}",
        f"102,2,{word()} {word()} {word()}",
        f"103,5,{word()};::{word()}?{word()}.{word()}",
        f"104,4,{word()}!{word()}",
        f"105,5,{word()}\t{word()}   {word()}:{word()}",
        f"106,1,{word()}.{word()}",
    ]
    return "\n".join(rows) + "\n"


@pytest.fixture(scope="session", autouse=True)
def run_submitted_pipeline_on_original_input():
    assert os.path.exists(SCRIPT_PATH), f"The bash script {SCRIPT_PATH} is missing."
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    subprocess.run([SCRIPT_PATH], cwd="/home/user", check=True, timeout=30)


def test_analyze_c_exists():
    assert os.path.exists(SOURCE_PATH), "The C source file /home/user/analyze.c is missing."
    assert os.path.isfile(SOURCE_PATH), "/home/user/analyze.c is not a regular file."


def test_run_pipeline_sh_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The bash script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_analysis_result():
    assert os.path.exists(CSV_PATH), f"Input file {CSV_PATH} is missing."
    assert_result_matches()


def test_source_and_pipeline_are_functional():
    original_csv = open(CSV_PATH, "rb").read()
    original_result = open(RESULT_PATH, "rb").read()
    direct_exe = "/tmp/verifier_direct_analyze"
    wrapper_dir = "/tmp/verifier-gcc-bin"
    gcc_log = "/tmp/verifier-gcc.log"
    source_seen = "/tmp/verifier-gcc-source-seen"
    execution_marker = "/tmp/verifier-compiled-executed"

    try:
        # Independently compile and execute the submitted C source on fresh data.
        with open(CSV_PATH, "w") as f:
            f.write(random_dataset())
        subprocess.run(
            ["/usr/bin/gcc", SOURCE_PATH, "-o", direct_exe, "-lm"],
            check=True,
            timeout=30,
        )
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        subprocess.run([direct_exe], cwd="/home/user", check=True, timeout=30)
        assert_result_matches()

        # Exercise the submitted script on different fresh data. The gcc shim
        # forwards to the real compiler and wraps its linked executable so that
        # running that executable leaves an execution marker.
        with open(CSV_PATH, "w") as f:
            f.write(random_dataset())
        os.makedirs(wrapper_dir, exist_ok=True)
        for path in (gcc_log, source_seen, execution_marker):
            if os.path.exists(path):
                os.remove(path)

        wrapper = r'''#!/bin/bash
set -e
printf '%q ' "$@" >> /tmp/verifier-gcc.log
printf '\n' >> /tmp/verifier-gcc.log
out=a.out
linked=1
saw_source=0
need_out=0
for arg in "$@"; do
    if [ "$need_out" = 1 ]; then
        out="$arg"
        need_out=0
        continue
    fi
    case "$arg" in
        -o) need_out=1 ;;
        -c|-E|-S) linked=0 ;;
    esac
    if [ "$(basename -- "$arg")" = analyze.c ]; then
        saw_source=1
    fi
done
/usr/bin/gcc "$@"
if [ "$saw_source" = 1 ]; then
    touch /tmp/verifier-gcc-source-seen
fi
if [ "$linked" = 1 ] && [ -e /tmp/verifier-gcc-source-seen ]; then
    case "$out" in
        /*) target="$out" ;;
        *) target="$PWD/$out" ;;
    esac
    if [ -f "$target" ] && [ -x "$target" ]; then
        real="${target}.verifier_real"
        mv -f "$target" "$real"
        printf '#!/bin/bash\necho ran >> /tmp/verifier-compiled-executed\nexec %q "$@"\n' "$real" > "$target"
        chmod +x "$target"
    fi
fi
'''
        wrapper_path = os.path.join(wrapper_dir, "gcc")
        with open(wrapper_path, "w") as f:
            f.write(wrapper)
        os.chmod(wrapper_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        subprocess.run([SCRIPT_PATH], cwd="/home/user", env=env, check=True, timeout=30)

        assert os.path.exists(source_seen), "run_pipeline.sh did not compile analyze.c using gcc."
        assert os.path.exists(execution_marker), (
            "run_pipeline.sh did not run the executable produced by its gcc compilation."
        )
        assert_result_matches()
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(RESULT_PATH, "wb") as f:
            f.write(original_result)
        if os.path.exists(direct_exe):
            os.remove(direct_exe)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
