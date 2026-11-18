#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 <<'PY'
import base64
import os
import pwd
import random
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import time

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "process_data.sh")
RAW = os.path.join(HOME, "raw_data.txt")
OUTPUT = os.path.join(HOME, "final_output.txt")
KEY_FILE = os.path.join(HOME, "xor_key.txt")
DECODER = os.path.join(HOME, "decoder")
EXPECTED_ORIGINAL = [
    "ALFA", "BRAVO", "CHARLIE", "DELTA", "ECHO",
    "FOXTROT", "GOLF", "HOTEL", "INDIA", "JULIETT"
]


def tree_paths(root):
    result = set()
    if not os.path.exists(root):
        return result
    for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
        for name in dirs + files:
            result.add(os.path.join(base, name))
    return result


def read_output():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} does not exist."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def run_script(check_temp_cleanup=True):
    before_home = tree_paths(HOME)
    before_tmp = tree_paths("/tmp")

    user = pwd.getpwnam("user")
    env = os.environ.copy()
    env.update({"HOME": HOME, "USER": "user", "LOGNAME": "user", "LC_ALL": "C"})

    def demote():
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        [SCRIPT], cwd=HOME, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30, preexec_fn=demote
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    if check_temp_cleanup:
        after_home = tree_paths(HOME)
        after_tmp = tree_paths("/tmp")
        new_home = after_home - before_home - {OUTPUT}
        new_tmp = after_tmp - before_tmp
        assert not new_home, f"Script left temporary paths in {HOME}: {sorted(new_home)}"
        assert not new_tmp, f"Script left temporary paths in /tmp: {sorted(new_tmp)}"
        assert not os.path.exists(os.path.join(HOME, "tmp.out")), \
            "Script left /home/user/tmp.out behind."


assert os.path.isfile(KEY_FILE), f"File {KEY_FILE} does not exist."
with open(KEY_FILE, "r", encoding="utf-8") as f:
    key_content = f.read().strip().lower()
assert key_content == "0x42", f"Expected '0x42' in {KEY_FILE}, but found '{key_content}'."

assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} must be a regular file."
assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."
with open(SCRIPT, "r", encoding="utf-8") as f:
    script_content = f.read()
assert "&" in script_content, f"The script {SCRIPT} must use '&' for concurrent processing."
syntax = subprocess.run(["bash", "-n", SCRIPT], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert syntax.returncode == 0, f"Invalid Bash syntax in {SCRIPT}: {syntax.stderr}"

assert os.path.isfile(DECODER), f"File {DECODER} does not exist."
assert os.access(DECODER, os.X_OK), f"{DECODER} is not executable."

with open(RAW, "rb") as f:
    original_raw = f.read()

real_decoder = DECODER + ".verifier-real"
probe_dir = tempfile.mkdtemp(prefix="pipeline-probe-")
lock_path = os.path.join(probe_dir, "lock")
active_path = os.path.join(probe_dir, "active")
max_path = os.path.join(probe_dir, "max")
renamed = False

try:
    # Execute the submitted script on the supplied artifact before checking it.
    run_script()
    original_lines = read_output()
    assert original_lines == EXPECTED_ORIGINAL, (
        f"Content of {OUTPUT} does not match the expected sorted output. "
        f"Found: {original_lines}"
    )

    assert not os.path.exists(real_decoder), f"Unexpected path already exists: {real_decoder}"
    os.rename(DECODER, real_decoder)
    renamed = True

    for path, value in ((active_path, "0\n"), (max_path, "0\n"), (lock_path, "")):
        with open(path, "w", encoding="ascii") as f:
            f.write(value)
        os.chmod(path, 0o666)

    wrapper = f'''#!/bin/bash
exec 9>"{lock_path}"
flock 9
active=$(cat "{active_path}")
active=$((active + 1))
echo "$active" > "{active_path}"
maximum=$(cat "{max_path}")
if [ "$active" -gt "$maximum" ]; then
    echo "$active" > "{max_path}"
fi
flock -u 9
sleep 0.04
"{real_decoder}" "$@"
rc=$?
flock 9
active=$(cat "{active_path}")
echo $((active - 1)) > "{active_path}"
flock -u 9
exit "$rc"
'''
    with open(DECODER, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(DECODER, 0o755)

    # Randomized inputs prevent a fixed-output submission from passing. The
    # delayed decoder also measures real overlap rather than trusting a grep.
    for trial in range(3):
        labels = []
        while len(labels) < 90:
            label = "ITEM-" + secrets.token_hex(8).upper()
            if label not in labels:
                labels.append(label)
        labels += labels[:12]
        labels += ["SPACE VALUE", "ZULU VALUE", "ALPHA VALUE"]
        random.SystemRandom().shuffle(labels)

        encoded = []
        for text in labels:
            cipher = bytes(byte ^ 0x42 for byte in text.encode("ascii"))
            encoded.append(base64.b64encode(cipher).decode("ascii"))
        with open(RAW, "w", encoding="ascii", newline="\n") as f:
            f.write("\n".join(encoded) + "\n")

        with open(active_path, "w", encoding="ascii") as f:
            f.write("0\n")
        with open(max_path, "w", encoding="ascii") as f:
            f.write("0\n")

        run_script()
        actual = read_output()
        expected = sorted(labels)
        assert actual == expected, (
            f"Dynamic decoding/sorting trial {trial + 1} failed. "
            f"Expected {expected}, found {actual}"
        )
        with open(active_path, "r", encoding="ascii") as f:
            active = int(f.read().strip())
        with open(max_path, "r", encoding="ascii") as f:
            maximum = int(f.read().strip())
        assert active == 0, "The script returned before all decoder jobs completed."
        assert maximum > 1, (
            "Decoder invocations did not overlap; '&' must be used for actual concurrent processing."
        )

finally:
    with open(RAW, "wb") as f:
        f.write(original_raw)
    if renamed:
        try:
            os.remove(DECODER)
        except FileNotFoundError:
            pass
        if os.path.exists(real_decoder):
            os.rename(real_decoder, DECODER)
    shutil.rmtree(probe_dir, ignore_errors=True)

# Leave and verify the requested final state using the supplied raw data.
run_script()
final_lines = read_output()
assert final_lines == EXPECTED_ORIGINAL, (
    f"Content of {OUTPUT} does not match the expected sorted output after rerun. "
    f"Found: {final_lines}"
)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
