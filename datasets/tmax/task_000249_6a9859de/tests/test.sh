#!/bin/bash
set -u
mkdir -p /logs/verifier

echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_backup_chunks_exist_and_correct():
    backup_dir = "/home/user/backup_chunks"

    assert os.path.isdir(backup_dir), f"Directory {backup_dir} does not exist."

    expected_files = ["xaa", "xab", "xac"]
    actual_files = os.listdir(backup_dir)
    assert set(actual_files) == set(expected_files), (
        f"Expected exactly files {expected_files} in {backup_dir}, "
        f"but found {actual_files}."
    )

    expected_contents = {
        "xaa": "A" * 100,
        "xab": ("A" * 20) + ("C" * 80),
        "xac": "C" * 50
    }

    for filename, expected_content in expected_contents.items():
        filepath = os.path.join(backup_dir, filename)
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing."

        actual_size = os.path.getsize(filepath)
        expected_size = len(expected_content)
        assert actual_size == expected_size, (
            f"File {filepath} has incorrect size. Expected {expected_size}, got {actual_size}."
        )

        with open(filepath, "r") as f:
            actual_content = f.read()

        assert actual_content == expected_content, (
            f"File {filepath} has incorrect content."
        )
TEST_EOF

# Preserve the original final-state assertions.
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    exit 0
fi

# Locate scripts/programs authored by the agent before adding verifier fixtures.
python3 - << 'PY' > /tmp/backup_candidates.list
import os

excluded = (
    "/home/user/app_config",
    "/home/user/backup_chunks",
    "/home/user/staging_backup",
)
roots = ["/home/user", "/root", "/tmp"]
candidates = []
for root in roots:
    if not os.path.isdir(root):
        continue
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        if any(dirpath == p or dirpath.startswith(p + os.sep) for p in excluded):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d not in {".cache", "__pycache__"}]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if path.startswith("/tmp/test_final_state.py") or path.startswith("/tmp/backup_candidates"):
                continue
            try:
                if not os.path.isfile(path):
                    continue
                with open(path, "rb") as f:
                    first = f.readline(256)
                scripted = name.endswith((".sh", ".bash", ".py")) or first.startswith(b"#!")
                if scripted or os.access(path, os.X_OK):
                    candidates.append((os.stat(path).st_mtime_ns, path))
            except OSError:
                pass
for _, path in sorted(candidates, reverse=True):
    print(path)
PY

if [ ! -s /tmp/backup_candidates.list ]; then
    echo "No executable backup artifact was found." >&2
    exit 0
fi

# Replace the source data with unpredictable inputs. This exercises recency,
# basename ordering, a followed file symlink, and the existing directory loop.
python3 - << 'PY'
import json, os, secrets, time

base = "/home/user/app_config"
os.makedirs(os.path.join(base, "dirA"), exist_ok=True)

def payload(tag, n):
    token = secrets.token_hex(24).encode()
    return (tag.encode() + b":" + token + b"|") * n

files = {
    os.path.join(base, "alpha.conf"): payload("alpha", 5),
    os.path.join(base, "file1.conf"): payload("file1", 4),
    os.path.join(base, "file3.conf"): payload("file3", 6),
    os.path.join(base, "zeta.ini"): payload("zeta", 3),
}
for path, data in files.items():
    with open(path, "wb") as f:
        f.write(data)
    os.utime(path, None)

old = os.path.join(base, "file2.conf")
with open(old, "wb") as f:
    f.write(payload("OLD-MUST-NOT-APPEAR", 5))
two_days_ago = time.time() - 2 * 86400
os.utime(old, (two_days_ago, two_days_ago))

external = "/home/user/verifier_external_config.dat"
with open(external, "wb") as f:
    f.write(payload("linked", 4))
os.utime(external, None)
link = os.path.join(base, "mid.conf")
try:
    os.unlink(link)
except FileNotFoundError:
    pass
os.symlink(external, link)

ordered = [
    files[os.path.join(base, "alpha.conf")],
    files[os.path.join(base, "file1.conf")],
    files[os.path.join(base, "file3.conf")],
    open(external, "rb").read(),
    files[os.path.join(base, "zeta.ini")],
]
merged = b"".join(ordered)
chunks = [merged[i:i+100] for i in range(0, len(merged), 100)]

def suffix(i):
    # GNU split's default two-letter suffix sequence for this small fixture.
    return chr(ord('a') + i // 26) + chr(ord('a') + i % 26)

expected = {"x" + suffix(i): chunk.hex() for i, chunk in enumerate(chunks)}
with open("/tmp/dynamic_expected.json", "w") as f:
    json.dump(expected, f)
PY

# Intercept split itself, including absolute /usr/bin/split invocations. The
# wrapper records only staging files created or changed by split. Their inodes
# must subsequently appear in the final directory, proving staging then move.
SPLIT_REAL=/usr/bin/split.verifier-real
if [ -e "$SPLIT_REAL" ]; then
    rm -f "$SPLIT_REAL"
fi
mv /usr/bin/split "$SPLIT_REAL"
restore_split() {
    if [ -e "$SPLIT_REAL" ]; then
        rm -f /usr/bin/split
        mv "$SPLIT_REAL" /usr/bin/split
    fi
}
trap restore_split EXIT

cat << 'WRAP_EOF' > /usr/bin/split
#!/bin/bash
before=$(mktemp)
python3 - "$before" << 'PY'
import hashlib, json, os, sys
out = {}
d = "/home/user/staging_backup"
if os.path.isdir(d):
    for n in os.listdir(d):
        p = os.path.join(d, n)
        if os.path.isfile(p):
            try:
                with open(p, "rb") as f:
                    out[n] = hashlib.sha256(f.read()).hexdigest()
            except OSError:
                pass
with open(sys.argv[1], "w") as f:
    json.dump(out, f)
PY
/usr/bin/split.verifier-real "$@"
status=$?
if [ "$status" -eq 0 ]; then
python3 - "$before" << 'PY'
import hashlib, json, os, sys
try:
    with open(sys.argv[1]) as f:
        before = json.load(f)
except Exception:
    before = {}
d = "/home/user/staging_backup"
if os.path.isdir(d):
    with open("/tmp/split_staging.log", "a") as log:
        for n in os.listdir(d):
            p = os.path.join(d, n)
            if not os.path.isfile(p):
                continue
            try:
                with open(p, "rb") as f:
                    digest = hashlib.sha256(f.read()).hexdigest()
                if before.get(n) != digest:
                    st = os.stat(p)
                    log.write(f"{n}\t{st.st_dev}\t{st.st_ino}\n")
            except OSError:
                pass
PY
fi
rm -f "$before"
exit "$status"
WRAP_EOF
chmod 755 /usr/bin/split

cat << 'PY' > /tmp/check_dynamic.py
import json, os, sys

backup = "/home/user/backup_chunks"
staging = "/home/user/staging_backup"
with open("/tmp/dynamic_expected.json") as f:
    expected = {name: bytes.fromhex(data) for name, data in json.load(f).items()}

if not os.path.isdir(backup):
    sys.exit(1)
actual_names = os.listdir(backup)
if set(actual_names) != set(expected):
    sys.exit(1)

recorded = {}
try:
    with open("/tmp/split_staging.log") as f:
        for line in f:
            name, dev, ino = line.rstrip("\n").split("\t")
            recorded.setdefault(name, set()).add((int(dev), int(ino)))
except (OSError, ValueError):
    sys.exit(1)

for name, wanted in expected.items():
    path = os.path.join(backup, name)
    if not os.path.isfile(path) or os.path.islink(path):
        sys.exit(1)
    with open(path, "rb") as f:
        if f.read() != wanted:
            sys.exit(1)
    st = os.stat(path)
    if (st.st_dev, st.st_ino) not in recorded.get(name, set()):
        sys.exit(1)

# Every split-created chunk must have been moved out of staging.
if not os.path.isdir(staging):
    sys.exit(1)
if any(name.startswith("x") for name in os.listdir(staging)):
    sys.exit(1)
sys.exit(0)
PY

passed=0
while IFS= read -r candidate; do
    [ -f "$candidate" ] || continue
    rm -rf /home/user/staging_backup
    mkdir -p /home/user/backup_chunks
    find /home/user/backup_chunks -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    : > /tmp/split_staging.log

    first=$(head -c 2 "$candidate" 2>/dev/null || true)
    case "$candidate" in
        *.py) runner=(python3 "$candidate") ;;
        *.sh|*.bash) runner=(bash "$candidate") ;;
        *)
            if [ "$first" = "#!" ] || [ -x "$candidate" ]; then
                runner=("$candidate")
            else
                continue
            fi
            ;;
    esac

    candidate_dir=$(dirname "$candidate")
    if (cd "$candidate_dir" && timeout 15s "${runner[@]}") >/tmp/candidate.out 2>/tmp/candidate.err; then
        if python3 /tmp/check_dynamic.py; then
            passed=1
            break
        fi
    fi
done < /tmp/backup_candidates.list

restore_split
trap - EXIT

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "Dynamic execution did not produce split-generated chunks staged and moved correctly." >&2
fi
