# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the license found in the
# LICENSE file in the root directory of this source tree.

"""TestamentSuite suite adapter."""

import os
import json
import re

from ..base import ReproductionSuite
from ..utils.compiled import _patched_files, _run
from ..utils.logging import log

# Testament prints one line per result. The name it prints is the whole identity of the
# run — `tests/stdlib/tmarshal.nim c --mm:orc` — because one case is compiled once per
# backend *and* once per extra option set, and those runs have different outcomes. It is
# padded to 60 columns and followed by ` ( N.NN sec)`; the skip forms carry no duration.
_RESULT_RE = re.compile(r"^(?P<verdict>PASS|FAIL|SKIP|NOTINBATCH|JOINED):\s+(?P<name>\S.*?)\s*$")
# The duration testament appends to a non-skipped result.
_DURATION_RE = re.compile(r"\(\s*[\d.]+ sec\)$")
_VERDICTS = {
    "PASS": "passed",
    "FAIL": "failed",
    "SKIP": "skipped",
    "NOTINBATCH": "skipped",
    "JOINED": "skipped",
}


class TestamentSuite(ReproductionSuite):
    """One ``testament r <file>`` process per touched test file.

    Nim's corpus is **one program per case**: ``tests/<category>/t<name>.nim`` is a
    complete Nim program whose expected compiler output, expected stdout and exit code are
    written in a spec comment at the top of the file itself. Testament compiles it, runs
    it, and diffs both against the spec. There is no test *function* below the file, so
    ``names`` is always empty and the file is the unit — the same shape as the Perl and
    Rust UI corpora.

    Whole-corpus runs enable backend JSON logging on the image's baseline branch.
    Selected hidden cases disable it so detached per-bug worktrees remain supported.
    Megatests are disabled to retain individual case outcomes, and colors are disabled
    for the console parser used by selected cases.

    ``targets`` only accepts files testament itself would run: a case's basename starts
    with ``t``. Everything else under ``tests/`` is a helper module a case imports, and
    handing one to ``testament r`` makes it compile a module with no spec.

    ``nim`` is the compiler binary the cases are compiled with, relative to the repo — the
    per-subtask rebuild refreshes exactly that path.
    """

    no_targets = "test patch touched no testament case"

    def __init__(self, test_roots=("tests",), nim="bin/nim", testament="testament/testament", targets=()):
        self.test_roots = list(test_roots)
        self.nim = nim
        self.testament = testament
        self.targets_flag = list(targets)

    def _under_test_root(self, path):
        return any(path == root or path.startswith(root + "/") for root in self.test_roots)

    def targets(self, diff, env=None):
        """``([test file paths], [])`` — see the class docstring on why names stay empty."""
        del env
        found = []
        for path in _patched_files(diff):
            if not path.endswith(".nim") or not self._under_test_root(path):
                continue
            if not os.path.basename(path).startswith("t"):
                continue
            if path not in found:
                found.append(path)
        return sorted(found), []

    def _command(self, case):
        """``testament r <case>``, or ``testament all`` for the whole corpus.

        The visible suite is **one** process, not one per case: the corpus is some twenty
        thousand programs and testament already walks it itself, so spawning a process each
        would spend the whole timeout on process startup."""
        cmd = [
            "./" + self.testament,
            "--nim:" + self.nim,
            "--backendLogging:on" if case is None else "--backendLogging:off",
            "--colors:off",
            "--megatest:off",
        ]
        if self.targets_flag:
            cmd.append("--targets:" + " ".join(self.targets_flag))
        return cmd + (["all"] if case is None else ["r", case])

    def run_tests(self, env, repo, files, names, timeout, jobs):
        """Run each case in its own testament process and parse the verdicts it prints."""
        del names, jobs
        cases = [None] if files is None else list(files)
        outcomes = {}
        error = False
        for case in cases:
            if case is None:
                env.execute(["rm", "-rf", os.path.join(repo, "testresults")])
            result = _run(env, self._command(case), timeout=timeout, cwd=repo)
            if result is None:
                log("testament %s TIMEOUT after %ds" % (case or "all", timeout))
                return outcomes, 0, False, True
            log("testament %s rc=%d" % (case or "all", result.returncode))
            log(result.stdout[-2500:])
            if case is None:
                # Parallel category workers interleave console bytes, including test names.
                # The baseline checkout retains a branch, so native JSON logging works.
                reports = [p for p in env.find_files(os.path.join(repo, "testresults")) if p.endswith(".json")]
                seen = 0
                for report in reports:
                    try:
                        records = json.loads(env.read_text(report))
                    except (OSError, ValueError) as exc:
                        log("unreadable testament report %s: %s" % (report, exc))
                        outcomes["<report:%s>" % os.path.basename(report)] = "error"
                        error = True
                        continue
                    for record in records:
                        status = record["result"]
                        outcomes[record["name"].strip()] = ("passed" if status == "reSuccess" else
                            "skipped" if status in {"reDisabled", "reJoined"} else "failed")
                        seen += 1
            else:
                seen = self._parse(case, result.stdout, outcomes)
            # No verdict at all means testament never got as far as the case — a missing
            # compiler, a broken spec parse. That is the `error` flag, not a failure:
            # "the harness did not run" and "the test failed" differ post-gold.
            if not seen and result.returncode != 0:
                error = True
        n = len([value for value in outcomes.values() if value != "skipped"])
        return outcomes, n, error, False

    @staticmethod
    def _parse(case, text, outcomes):
        """Fold one testament run's verdicts into ``outcomes``; return how many it printed.

        The key is testament's own name for the run, not the file: one case is compiled
        once per backend and once per extra option set, and `--mm:orc` failing while
        `--mm:refc` passes is the ordinary shape of a memory-management fix. Keying on the
        path alone would let the last line win and hide the failure."""
        seen = 0
        text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
        for line in text.splitlines():
            match = _RESULT_RE.match(line.strip())
            if match is None:
                continue
            name = _DURATION_RE.sub("", match.group("name")).strip()
            if ".nim" not in name.split(" ")[0]:
                continue
            seen += 1
            outcomes[name] = _VERDICTS[match.group("verdict")]
        return seen
