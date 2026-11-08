#!/bin/bash
set -uo pipefail

WORKDIR=/fescar
TEST_FILES=(test/pom.xml)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
if python3 - <<'PY'
import re
import xml.etree.ElementTree as ET
from pathlib import Path

expected = "0.2.1-SNAPSHOT"
root = ET.parse("pom.xml").getroot()
namespace = root.tag.split("}", 1)[0] + "}" if "}" in root.tag else ""
find = lambda node, path: node.find("/".join(namespace + part for part in path.split("/")))

def properties(pom):
    node = find(pom, "properties")
    return {child.tag.split("}")[-1]: (child.text or "").strip() for child in node} if node is not None else {}

def resolved_version(node, values, description):
    assert node is not None and node.text, description + " must be declared"
    value = node.text.strip()
    for _ in range(len(values) + 1):
        updated = re.sub(r"\$\{([^}]+)\}", lambda match: values.get(match.group(1), match.group(0)), value)
        if updated == value:
            break
        value = updated
    assert value == expected, description + " must resolve to " + expected

root_properties = properties(root)
resolved_version(find(root, "version"), root_properties, "root Maven version")
modules = find(root, "modules")
for module in modules:
    name = module.text.strip()
    pom = ET.parse(str(Path(name) / "pom.xml")).getroot()
    values = dict(root_properties)
    values.update(properties(pom))
    parent = find(pom, "parent")
    parent_version = find(parent, "version") if parent is not None else None
    own_version = find(pom, "version")
    resolved_version(parent_version, values, name + " parent Maven version")
    if own_version is not None:
        resolved_version(own_version, values, name + " Maven version")
PY
then
  mvn test --no-transfer-progress -DtrimStackTrace=false
else
  false
fi
HARBOR_TEST_CMD_EOF

V=/logs/verifier
mkdir -p "$V"
echo 0 > "$V/reward.txt"
cd "$WORKDIR"
EXCLUDES=(.gitmodules '*.tar.gz' '*.tgz' '*.zip' '*.rej')

apply_patch() (
  set +eu +o pipefail
  git reset -q || true
  git update-index -q --refresh || true
  ex=()
  for e in "${EXCLUDES[@]}"; do ex+=("--exclude=$e"); done
  apply=(git apply --verbose "${ex[@]}" --whitespace=nowarn)
  "${apply[@]}" "$1" 2>&1 && exit 0
  keep=()
  while IFS= read -r path; do
    glob=$(printf '%s' "$path" | sed 's/[][*?\\]/\\&/g')
    git apply --summary --include="$glob" "$1" | grep -q "^ create mode" &&
      [ -z "$(git apply --check -R --whitespace=nowarn --include="$glob" "$1" 2>&1)" ] && keep+=("--exclude=$glob")
  done < <(LC_ALL=C "${apply[@]}" --check "$1" 2>&1 | sed -n 's/^error: \(.*\): already exists in working directory$/\1/p')
  "${apply[@]}" "${keep[@]}" "$1" 2>&1 && exit 0
  [ -z "$(git apply --check -R --whitespace=nowarn "${ex[@]}" "$1" 2>&1)" ] && exit 0
  "${apply[@]}" "${keep[@]}" --reject "$1" 2>&1
  exit 1
)

for f in "${TEST_FILES[@]}"; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then git restore "$f" 2>/dev/null; else rm -f "$f"; fi
done
cp /tests/test.patch /tmp/test.patch
if ! apply_patch /tmp/test.patch > "$V/test_patch_apply.log" 2>&1; then
  echo "TEST_PATCH_APPLY_FAILED"
  cat "$V/test_patch_apply.log"
  exit 0
fi

export HARBOR_TEST_CMD="${HARBOR_TEST_CMD%$'\n'}"
bash -lc 'timeout -k 10 1800 bash -lc "$HARBOR_TEST_CMD"' 2>&1 | cat > "$V/test_output.log"
echo "test_cmd exit code: ${PIPESTATUS[0]}"

for PY in /opt/harbor-grader/python3 python3 python /opt/conda/bin/python3 ""; do
  PY=$(command -v "$PY" 2>/dev/null) && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null && break
done
if [ -z "$PY" ]; then
  echo "GRADER_PYTHON_UNAVAILABLE: the image has no Python >= 3.8"
  exit 0
fi
if "$PY" -I -S /tests/grade.py /tests/config.json "$V/test_output.log" "$V/report.json" "$V/test_results.json"; then
  echo 1 > "$V/reward.txt"
fi
