lint-staged will execute "Stashing changes" logic even if no lint-staged.conf.js files are changed or staged
### Description
In our repository we have Java code and front-end code such as TypeScript/SCSS etc.
We do not want any of our frontend tools to get in the way of our Java developers or make their development experience worse.

However, currently if a Java dev stages some code while leaving some other code unstaged, they end up hitting some special behaviour where lint-staged takes up to 90-120 seconds stashing changes.
```sh
frontend\src\node_modules\.bin\lint-staged
  / Stashing changes...
```

I feel this shouldn't occur because my lint-staged config only targets *.ts, *.tsx and *.scss files. It does not have any rules regarding *.java files. Is it possible to make sure that the staged files match at least one of the linters before doing this stashing logic?

I say this because there are also cases where a Java dev might have some *.ts files modified on their local machine that are unstaged. If they're only committing *.java files, then the linter shouldn't kick in.

### Steps to reproduce

**lint-staged.conf.js**
```js
'use-strict';

module.exports = {
	"linters": {
		"*.{ts,tsx}": [
			"tslint --fix",
			"git add"
		],
		"*.{scss}": [
			"stylelint --fix",
			"git add"
		]
	},
	"relative": true
}
```

**Example of Git status:**
Stage a hunk of a file that is not configured in the lint-staged.conf.js file.
```
Changes to be committed:
  (use "git reset HEAD <file>..." to unstage)

        modified:   backend/src/MyJavaFile.java

Changes not staged for commit:
  (use "git add/rm <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

        modified:   backend/src/MyJavaFile.java
```

### Debug Logs

**Note:** Pathnames have been obfuscated.
```
{$PATH}\frontend\src>yarn lint-staged --debug
yarn run v1.5.1
$ frontend/src/node_modules\.bin\lint-staged --debug
  lint-staged:bin Running `lint-staged@8.1.0` +0ms
  lint-staged:find-bin Loaded package.json using `process.cwd()` +0ms
  lint-staged Loading config using `cosmiconfig` +0ms
  lint-staged Successfully loaded config from `frontend/src/lint-staged.config.js`:
  lint-staged { linters:
  lint-staged    { '*.{ts,tsx}': [ 'tslint --fix', 'git add' ],
  lint-staged      '*.{scss}': [ 'stylelint --fix', 'git add' ] },
  lint-staged   relative: true } +14ms
  lint-staged:cfg Normalizing config +0ms
  lint-staged:cfg Validating config +2ms
Running lint-staged with the following config:
{
  linters: {
    '*.{ts,tsx}': [
      'tslint --fix',
      'git add'
    ],
    '*.{scss}': [
      'stylelint --fix',
      'git add'
    ]
  },
  relative: true,
  concurrent: true,
  chunkSize: 9007199254740991,
  globOptions: {
    matchBase: true,
    dot: true
  },
  ignore: [],
  subTaskConcurrency: 1,
  renderer: 'verbose'
}
  lint-staged:run Running all linter scripts +0ms
  lint-staged:run Resolved git directory to be `\` +2ms
  lint-staged:run Loaded list of staged files in git:
  lint-staged:run [ 'backend/src/MyJavaFile.java' ] +83ms
  lint-staged:gen-tasks Generating linter tasks +0ms
  lint-staged:cfg Normalizing config +93ms
  lint-staged:gen-tasks Generated task:
  lint-staged:gen-tasks { pattern: '*.{ts,tsx}',
  lint-staged:gen-tasks   commands: [ 'tslint --fix', 'git add' ],
  lint-staged:gen-tasks   fileList: [] } +2ms
  lint-staged:gen-tasks Generated task:
  lint-staged:gen-tasks { pattern: '*.{scss}',
  lint-staged:gen-tasks   commands: [ 'stylelint --fix', 'git add' ],
  lint-staged:gen-tasks   fileList: [] } +1ms
Stashing changes... [started]
  lint-staged:git Stashing files... +0ms
  lint-staged:git Running git command [ 'write-tree' ] +1ms
  lint-staged:git Running git command [ 'add', '.' ] +79ms
  lint-staged:git Running git command [ 'write-tree' ] +318ms
  lint-staged:git Running git command [ 'read-tree', 'a9d6b6851fc7129a68ab841210558dbd918a8964' ] +102ms
  lint-staged:git Running git command [ 'checkout-index', '-af' ] +214ms
  lint-staged:git Done stashing files! +48s
Stashing changes... [completed]
Running linters... [started]
Running tasks for *.{ts,tsx} [started]
Running tasks for *.{scss} [started]
Running tasks for *.{ts,tsx} [skipped]
→ No staged files match *.{ts,tsx}
Running tasks for *.{scss} [skipped]
→ No staged files match *.{scss}
Running linters... [completed]
Updating stash... [started]
  lint-staged:git Running git command [ 'write-tree' ] +4ms
Updating stash... [completed]
Restoring local changes... [started]
  lint-staged:git Restoring working copy +72ms
  lint-staged:git Running git command [ 'read-tree', '2db37eb6009634a494b10446c26c0a18e47c95eb' ] +1ms
  lint-staged:git Running git command [ 'checkout-index', '-af' ] +216ms
  lint-staged:git Restoring index with formatting changes +47s
  lint-staged:git Running git command [ 'read-tree', 'a9d6b6851fc7129a68ab841210558dbd918a8964' ] +2ms
  lint-staged:git Generating diff between trees a9d6b6851fc7129a68ab841210558dbd918a8964 and a9d6b6851fc7129a68ab841210558dbd918a8964... +214ms
  lint-staged:git Running git command [ 'diff-tree',
  '--ignore-submodules',
  '--binary',
  '--no-color',
  '--no-ext-diff',
  '--unified=0',
  'a9d6b6851fc7129a68ab841210558dbd918a8964',
  'a9d6b6851fc7129a68ab841210558dbd918a8964' ] +2ms
  lint-staged:git Running git command [ 'apply',
  '-v',
  '--whitespace=nowarn',
  '--reject',
  '--recount',
  '--unidiff-zero' ] +78ms
  lint-staged:git Could not apply patch to the stashed files cleanly +55ms
  lint-staged:git Error: Error: Command failed: git apply -v --whitespace=nowarn --reject --recount --unidiff-zero
  lint-staged:git error: unrecognized input
  lint-staged:git
  lint-staged:git
  lint-staged:git     at execGit (frontend\src\node_modules\lint-staged\src\gitWorkflow.js:28:11)
  lint-staged:git     at <anonymous>
  lint-staged:git     at process._tickCallback (internal/process/next_tick.js:188:7) +2ms
  lint-staged:git Patch content: +0ms
  lint-staged:git
  lint-staged:git  +1ms
  lint-staged:git Found conflicts between formatters and local changes. Formatters changes will be ignored for conflicted hunks. +0ms
  lint-staged:git Deleted files and folders:
  lint-staged:git   +4ms
Restoring local changes... [completed]
  lint-staged linters were executed successfully! +2m
Done in 97.67s.
```

### Environment

- **OS:** Windows 10
- **Node.js:** v8.11.1
- **`lint-staged`:** v8.1.0
- **git:** git version 2.18.0.windows.1

### Additional contract requirements

- When no staged files match any configured linter globs, print `No staged files match any of provided globs.`
- When no staged files match any configured linter glob, do not stash or restore working-copy changes.
- When no staged files match any configured linter glob, do not execute linter commands.
