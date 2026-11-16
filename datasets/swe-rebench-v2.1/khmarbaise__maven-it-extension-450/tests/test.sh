#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/maven-it-extension
TEST_FILES=(itf-assertj/src/test/java/com/soebes/itf/extension/assertj/ArchiveAssertTest.java itf-assertj/src/test/java/com/soebes/itf/extension/assertj/LogAssertTest.java itf-assertj/src/test/java/com/soebes/itf/extension/assertj/MavenCacheResultAssertTest.java itf-assertj/src/test/java/com/soebes/itf/extension/assertj/MavenExecutionResultAssertTest.java itf-assertj/src/test/java/com/soebes/itf/extension/assertj/MavenLogAssertTest.java itf-assertj/src/test/java/com/soebes/itf/extension/assertj/MavenProjectResultAssertTest.java itf-examples/src/test/resources-its/com/soebes/itf/examples/MavenIntegrationIT/first_integration_test/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/MavenIntegrationIT/setup/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/MavenIntegrationIT/setup_2/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/defaults/DefaultsForAllIT/option_debug/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/goals/GoalsIT/goal_clean/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/goals/GoalsIT/goal_clean_compile/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/goals/GoalsIT/no_goals_at_all/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/goals/GoalsOnClassIT/goal_clean/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/goals/MetaAnnotationGoalIT/clean_verify/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/mps/xyz/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/mps/xyzp3/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/options/OptionsIT/no_options_at_all/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/options/OptionsIT/option_debug/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/options/OptionsIT/option_quiet_logfile/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/options/OptionsOnClassIT/option_debug/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/MetaAnnotationProfileIT/profile_1_2_3/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileIT/UnknownProfile/maven_project/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileIT/no_profile_at_all/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileIT/profile_1/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileIT/profile_1_2/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileIT/profile_1_2_3/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileOnClassIT/profile_1/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/ProfileOnClassIT/profile_1_2_3/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/profiles/packagewide/ProfileOnPackageIT/profile_1_2_3/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/properties/MetaAnnotationPropertiesIT/property_skiptests/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/properties/PropertiesIT/property_skiptests/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/properties/PropertiesOnClassIT/property_skiptests/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/properties/PropertiesOnNestedClassIT/Level1/property_skiptests/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/repository/MavenRepositoryNestedIT/NestedIT/repository_in_enclosing_class_directory/pom.xml itf-examples/src/test/resources-its/com/soebes/itf/examples/repository/MavenRepositoryNestedIT/repository_in_class_directory/pom.xml)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
mvn test -pl '!itf-documentation' --no-transfer-progress -B -e
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

if [ -s /logs/artifacts/model.patch ]; then
  if ! (EXCLUDES=(); apply_patch /logs/artifacts/model.patch) > "$V/model_patch_apply.log" 2>&1; then
    echo "MODEL_PATCH_APPLY_FAILED"
    cat "$V/model_patch_apply.log"
    exit 0
  fi
fi
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
