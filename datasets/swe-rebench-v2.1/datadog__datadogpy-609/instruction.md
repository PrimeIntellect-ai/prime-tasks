"import datadog" executes statements
**Describe the bug**
`import datadog` executes statements. [HIDDEN] This results in errors in our unit tests because the exit handler, `datadog.threadstats.ThreadStats.flush`, calls `log.debug` after the logging capture file has been closed.

**To Reproduce**
Steps to reproduce the behavior:
1. Create a Python file, p.py, containing only `import datadog`
2. Run pdb on p.py
3. Set a breakpoint on `.../datadog/threadstats/base.py:337`
4. Enter `c` to start execution
5. Once the breakpoint is hit, enter `bt` to see the backtrace leading back to `import datadog`

**Expected behavior**
`import datadog` should not execute any statements.

**Environment and Versions (please complete the following information):**
- datadogpy 0.36.0
- python 3.7

### Additional contract requirements

- A plain `import datadog` must not trigger a `ThreadStats` shutdown flush as an import-time side effect.
