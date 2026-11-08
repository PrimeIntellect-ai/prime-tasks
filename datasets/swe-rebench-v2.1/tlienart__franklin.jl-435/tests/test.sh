#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/Franklin.jl
TEST_FILES=(test/parser/markdown-extra.jl)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
julia --project=. -e '
using Franklin, Test, Markdown, Dates, Random
const F = Franklin
const R = joinpath(pwd(), "test")
F.FD_ENV[:SILENT_MODE] = true
F.FD_ENV[:STRUCTURE] = v"0.1"
isapproxstr(s1::AbstractString, s2::AbstractString) = isequal(map(s->replace(s, r"\s|\n"=>""), String.((s1, s2)))...)
const td = mktempdir()
flush_td() = (isdir(td) && rm(td; recursive=true); mkdir(td))
F.FOLDER_PATH[] = td
fd2html_td(e) = F.fd2html(e; dir=td)
function seval(st)
    F.def_GLOBAL_VARS!()
    F.def_GLOBAL_LXDEFS!()
    m = F.convert_md(st)
    h = F.convert_html(m)
    return h
end
gotd() = (flush_td(); cd(td); F.FOLDER_PATH[] = td)
function fs1()
    F.FD_ENV[:STRUCTURE] = v"0.1"
    gotd()
    empty!(F.PATHS)
    F.set_paths!()
    mkdir(F.PATHS[:src]); mkdir(F.PATHS[:src_pages]); mkdir(F.PATHS[:libs])
    mkdir(F.PATHS[:src_css]); mkdir(F.PATHS[:src_html]); mkdir(F.PATHS[:assets])
end
function fs2()
    F.FD_ENV[:STRUCTURE] = v"0.2"
    gotd()
    empty!(F.PATHS)
    F.set_paths!()
    mkdir(F.PATHS[:site]); mkdir(F.PATHS[:assets]); mkdir(F.PATHS[:css])
    mkdir(F.PATHS[:layout]); mkdir(F.PATHS[:libs]); mkdir(F.PATHS[:literate])
end
set_curpath(path) = (F.set_var!(F.LOCAL_VARS, "fd_rpath", path); F.locvar("fd_rpath"))
failed = false
for f in ("regexes.jl", joinpath("manager", "rss.jl"), joinpath("parser", "markdown-extra.jl"))
    try
        include(joinpath(R, f))
    catch e
        global failed = true
        showerror(stderr, e)
        println(stderr)
    end
end
failed && error("some tests failed")
' 2>&1
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
