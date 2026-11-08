[BUG]: panic: called `Option::unwrap()` on a `None` value
### Pre-submission checks

- [x] I am **not** filing a feature request. These should be filed via the feature request form instead.
- [x] I have looked through the [open issues](https://github.com/woodruffw/zizmor/issues?q=is%3Aissue+is%3Aopen+) for a duplicate report.

### Expected behavior

Zizmor doesn't crash

### Actual behavior

Zizmor crashes: https://github.com/docker/actions-toolkit/actions/runs/14377190560/job/40312292178#step:6:25

### Reproduction steps

Workflow can be found here: https://github.com/docker/octoguard/blob/main/.github/workflows/octoguard.yml

### Logs

```
+ zizmor --min-severity=medium --min-confidence=medium --persona=pedantic --no-online-audits --format=sarif .
 INFO zizmor: skipping impostor-commit: offline audits only requested
 INFO zizmor: skipping ref-confusion: offline audits only requested
 INFO zizmor: skipping known-vulnerable-actions: offline audits only requested
 INFO audit: zizmor: 🌈 completed ./.github/actions/macos-setup-qemu/action.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/build.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/buildx-lab-releases-json.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/buildx-releases-json.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/codeql.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/compose-lab-releases-json.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/compose-releases-json.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/docker-releases-json.yml
 INFO audit: zizmor: 🌈 completed ./.github/workflows/publish.yml
Well, this is embarrassing.

zizmor had a problem and crashed. To help us diagnose the problem you can send us a crash report.

We have generated a report file at "/tmp/zizmor/report-777a9d2d-7850-4854-8928-baa2252492b5.toml". Submit an issue or email with the subject of "zizmor Crash Report" and include the report as an attachment.

- Homepage: https://github.com/woodruffw/zizmor
- Authors: William Woodruff <william@yossarian.net>

We take privacy seriously, and do not perform any automated error collection. In order to improve the software, we rely on people to submit reports.

Thank you kindly!
```

Here is the report: [zizmor-crash-report.zip](https://github.com/user-attachments/files/19682310/zizmor-crash-report.zip)

```
"name" = "zizmor"
"operating_system" = "Ubuntu 24.4.0 (noble) [64-bit]"
"crate_version" = "1.5.2"
"explanation" = """
Panic occurred in file '/root/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/yamlpath-0.15.0/src/lib.rs' at line 462
"""
"cause" = "called `Option::unwrap()` on a `None` value"
"method" = "Panic"
"backtrace" = """
   0:     0x558b6eacb90c - rust_begin_unwind
   1:     0x558b6e6c65bf - core::panicking::panic_fmt::hf8ffc7c15bfb58a0
   2:     0x558b6e6c660b - core::panicking::panic::h209220e15dcf6e53
   3:     0x558b6e6c6968 - core::option::unwrap_failed::h12717cc50f158ee2
   [HIDDEN]
   8:     0x558b6eb654bc - zizmor::audit::Audit::audit_normal_job::h7b5056467dfeb94d
   9:     0x558b6eb6573d - zizmor::audit::Audit::audit_workflow::h3bc6c7e082082071
  10:     0x558b6eb688fc - zizmor::audit::Audit::audit::h9a0a2e05716d2a6b
  11:     0x558b6ebf474f - zizmor::run::h103574f0eb933b1c
  12:     0x558b6ebe0578 - zizmor::main::hc579d69b57ce3a97
  13:     0x558b6ec089b3 - std::sys::backtrace::__rust_begin_short_backtrace::hd296e1579dfe1c10
  14:     0x558b6ebe0294 - main
  15:     0x7fd9fca2a1ca - <unresolved>
  16:     0x7fd9fca2a28b - __libc_start_main
  17:     0x558b6e6e783e - _start
  18:                0x0 - <unresolved>
"""
```

### Additional context

Not directly related but is it possible to print the stacktrace instead of creating a report file through a flag or smth like that? Relates to https://github.com/docker/octoguard/issues/8

### Additional contract requirements

- When analyzing the workflow described in the issue with `--pedantic`, Zizmor must complete without crashing.
