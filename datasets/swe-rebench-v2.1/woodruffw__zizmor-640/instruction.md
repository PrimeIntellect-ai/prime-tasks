[BUG]: `template-injection` false-positive
### Pre-submission checks

- [x] I am **not** filing a feature request. These should be filed via the feature request form instead.
- [x] I have looked through the [open issues](https://github.com/woodruffw/zizmor/issues?q=is%3Aissue+is%3Aopen+) for a duplicate report.

### Expected behavior

I expected zizmor to understand the common GHA ternary idiom of `${{ expr && '' || '' }}`.

### Actual behavior

Actually, it flagged this code: `${{ matrix.target == 'x86_64-linux-gnu' && '-Demit-man-pages' || '' }}`

### Reproduction steps

1. Add a staticlly-defined matrix to a job
2. Try to add a build flag dependent on the target

### Logs

```plain text
DEBUG zizmor::state: using cache directory: "/Users/dukese01/.cache/zizmor"
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::gitignore: opened gitignore file: /Users/dukese01/.config/git/ignore
DEBUG collect_inputs:collect_from_dir{input_path="."}: globset: glob converted to regex: Glob { glob: "**/._*", re: "(?-u)^(?:/?|.*/)\\._[^/]*$", opts: GlobOptions { case_insensitive: false, literal_separator: true, backslash_escape: true, empty_alternates: false }, tokens: Tokens([RecursivePrefix, Literal('.'), Literal('_'), ZeroOrMore]) }
DEBUG collect_inputs:collect_from_dir{input_path="."}: globset: built glob set; 5 literals, 31 basenames, 11 extensions, 0 prefixes, 0 suffixes, 2 required extensions, 1 regexes
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::gitignore: opened gitignore file: ./.gitignore
DEBUG collect_inputs:collect_from_dir{input_path="."}: globset: built glob set; 0 literals, 4 basenames, 0 extensions, 0 prefixes, 0 suffixes, 0 required extensions, 0 regexes
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::gitignore: opened gitignore file: ./.git/info/exclude
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./mise.local.toml: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("/Users/dukese01/.config/git/ignore"), original: "mise.local.toml", actual: "**/mise.local.toml", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./.zig-cache: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.gitignore"), original: ".zig-cache", actual: "**/.zig-cache", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./zig-out: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.gitignore"), original: "zig-out", actual: "**/zig-out", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::gitignore: opened gitignore file: ./.jj/.gitignore
DEBUG collect_inputs:collect_from_dir{input_path="."}: globset: glob converted to regex: Glob { glob: "*", re: "(?-u)^[^/]*$", opts: GlobOptions { case_insensitive: false, literal_separator: true, backslash_escape: true, empty_alternates: false }, tokens: Tokens([ZeroOrMore]) }
DEBUG collect_inputs:collect_from_dir{input_path="."}: globset: built glob set; 0 literals, 0 basenames, 0 extensions, 0 prefixes, 0 suffixes, 0 required extensions, 1 regexes
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./.jj/reviews.json: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.jj/.gitignore"), original: "/*", actual: "*", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./.jj/.gitignore: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.jj/.gitignore"), original: "/*", actual: "*", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./.jj/working_copy: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.jj/.gitignore"), original: "/*", actual: "*", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./.jj/repo: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.jj/.gitignore"), original: "/*", actual: "*", is_whitelist: false, is_only_dir: false })))
DEBUG collect_inputs:collect_from_dir{input_path="."}: ignore::walk: ignoring ./.vscode: Ignore(IgnoreMatch(Gitignore(Glob { from: Some("./.gitignore"), original: ".vscode/", actual: "**/.vscode", is_whitelist: false, is_only_dir: true })))
DEBUG zizmor::config: no config discovered; loading default
DEBUG zizmor::config: loaded config: Config { rules: {} }
 INFO zizmor: skipping impostor-commit: can't run without a GitHub API token
 INFO zizmor: skipping ref-confusion: can't run without a GitHub API token
 INFO zizmor: skipping known-vulnerable-actions: can't run without a GitHub API token
 INFO audit: zizmor: 🌈 completed ./.github/workflows/ci.yaml
note[template-injection]: code injection via template expansion
  --> ./.github/workflows/ci.yaml:55:9
   |
55 |       - name: 🔧 Build
   |         -------------- note: this step
56 |         run: zig build -Dtarget=${{ matrix.target }} ${{ matrix.target == 'x86_64-linux-gnu' && '-Demit-man-pages' || '' }}
   |         ------------------------------------------------------------------------------------------------------------------- note: ${{ matrix.target == 'x86_64-linux-gnu' && '-Demit-man-pages' || '' }} may expand into attacker-controllable code
   |
   = note: audit confidence → Unknown

1 finding: 1 unknown, 0 informational, 0 low, 0 medium, 0 high
```

### Additional context

As I think about it, this workflow is better served with an `include` key on the matrix.

### Additional contract requirements

- Do not report the shown conditional matrix build-flag expression as a template-injection finding when the matrix value only controls which literal branch is selected.
- When reporting the existing `fromJson(steps.runs.outputs.data).workflow_runs[0].id` template-injection finding, the diagnostic annotation must read exactly `fromJson(steps.runs.outputs.data).workflow_runs[0].id may expand into attacker-controllable code`.
