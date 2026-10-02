# PI-SWESweep

Repaired SWE-sweep repository tasks from `facebookresearch/swe-sweep` at `48e6bf74e2b2b7d055dfd39612fc8a9d60556144`. This directory contains only validated repairs, not the other upstream tasks. It is a separate benchmark variant.

| Repository | Tracked bugs | Retained regression tests | Empty / gold oracle / regression |
| --- | ---: | ---: | --- |
| clippy | 76 | 1629 | 0 / 1 / 0 |
| cvc5 | 38 | 1872 | 0 / 1 / 0 |
| datafusion | 38 | 7466 | 0 / 1 / 0 |
| dmd | 112 | 3263 | 0 / 1 / 0 |
| netty | 96 | 9628 | 0 / 1 / 0 |
| oxc | 6 | 780 | 0 / 1 / 0 |
| phpspreadsheet | 9 | 5889 | 0 / 1 / 0 |
| rails | 140 | 20306 | 0 / 1 / 0 |
| sunpy | 15 | 2003 | 0 / 1 / 0 |
| swc | 19 | 59924 | 0 / 1 / 0 |
| symfony | 149 | 39497 | 0 / 1 / 0 |
| syn | 13 | 111 | 0 / 1 / 0 |
| tokio | 12 | 1260 | 0 / 1 / 0 |

Baselines are intersections of repeated pristine runs. Existing failing, skipped, unmeasurable, and recorded unstable cases are not treated as regression references. Oxc additionally excludes three regression IDs that are themselves tracked fail-to-pass tests, so its historical behavior changes are not mislabeled as regressions. The original ignored-test lists are preserved for hidden grading.

An empty stored regression baseline is rejected. The grader requires every recorded fail-to-pass ID to pass, except upstream process-level failure markers, which represent the selected invocation rather than a concrete case ID. Missing required tests cannot earn credit.

The oracle applies each gold independently. It does not prove the fixes compose into a single patch. Ordinary submissions are still subject to the regression gate. Each task includes `repair-validation.json` with baseline counts, evidence hashes, and control outcomes. Test coverage remains finite.

Agent images contain the source tree and tooling. Hidden tests and golds are in separate verifier images; only the collected Git patch crosses the boundary. Images are private to the Prime Intellect team. Dockerfiles and immutable content-derived image tags are included.

Repairs include test discovery and result parsing, dependency caches for offline operation, release-compatible dependencies, process isolation, and stable per-test regression identities. Benchmark source bugs and reference fixes are preserved. CVC5 retains local autoconf helper URLs so reset/reconfigure stays offline.

Upstream license: [LICENSE.upstream](LICENSE.upstream). Original copyright notices are retained.
