staged deleted files missing from StatusSummary->staged[]
Trying to figure out if this is a bug or I'm not understanding simple-git's status structure. Given the following `git status` CLI output, I would expect the staged deleted files to appear in the `git.status()` `staged` array property, but they are not.

**`git status`**
```
On branch master
Your branch is ahead of 'origin/master' by 1 commit.
  (use "git push" to publish your local commits)

Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        modified:   data/db.json
        deleted:    public/assets/16b8dd27-8c71-452d-a33a-bac16dfeb25b-ctyyFSsgG.jpg
        deleted:    public/assets/2bfeff0a-c2fd-4c1f-b7ce-d9aaa85ef9e0-GRyHQR8Wi.jpg
        deleted:    public/assets/rotterdam-_7T4AFdYM.png
        deleted:    public/assets/screen-shot-2020-11-04-at-84705-am-VnSkK4fMa.png
        deleted:    public/assets/screen-shot-2020-11-04-at-85706-am-qs3duZeeN.png
        deleted:    public/assets/screen-shot-2020-11-04-at-90017-am-FSMcon-hf.png
        deleted:    public/assets/screen-shot-2020-11-04-at-94134-am-zsYjqtTbv.png

Changes not staged for commit:
  (use "git add/rm <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   package-lock.json
        modified:   package.json
        modified:   src-backend/api-history.js
        modified:   src-backend/api.js
        modified:   src/views/History.vue
```

**`console.log(git.status())`**
```
StatusSummary {
  not_added: [],
  conflicted: [],
  created: [],
  deleted: [
    'public/assets/16b8dd27-8c71-452d-a33a-bac16dfeb25b-ctyyFSsgG.jpg',
    'public/assets/2bfeff0a-c2fd-4c1f-b7ce-d9aaa85ef9e0-GRyHQR8Wi.jpg',
    'public/assets/rotterdam-_7T4AFdYM.png',
    'public/assets/screen-shot-2020-11-04-at-84705-am-VnSkK4fMa.png',
    'public/assets/screen-shot-2020-11-04-at-85706-am-qs3duZeeN.png',
    'public/assets/screen-shot-2020-11-04-at-90017-am-FSMcon-hf.png',
    'public/assets/screen-shot-2020-11-04-at-94134-am-zsYjqtTbv.png'
  ],
  modified: [
    'data/db.json',
    'package-lock.json',
    'package.json',
    'src-backend/api-history.js',
    'src-backend/api.js',
    'src/views/History.vue'
  ],
  renamed: [],
  files: [
    FileStatusSummary {
      path: 'data/db.json',
      index: 'M',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'package-lock.json',
      index: ' ',
      working_dir: 'M'
    },
    FileStatusSummary {
      path: 'package.json',
      index: ' ',
      working_dir: 'M'
    },
    FileStatusSummary {
      path: 'public/assets/16b8dd27-8c71-452d-a33a-bac16dfeb25b-ctyyFSsgG.jpg',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'public/assets/2bfeff0a-c2fd-4c1f-b7ce-d9aaa85ef9e0-GRyHQR8Wi.jpg',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'public/assets/rotterdam-_7T4AFdYM.png',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'public/assets/screen-shot-2020-11-04-at-84705-am-VnSkK4fMa.png',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'public/assets/screen-shot-2020-11-04-at-85706-am-qs3duZeeN.png',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'public/assets/screen-shot-2020-11-04-at-90017-am-FSMcon-hf.png',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'public/assets/screen-shot-2020-11-04-at-94134-am-zsYjqtTbv.png',
      index: 'D',
      working_dir: ' '
    },
    FileStatusSummary {
      path: 'src-backend/api-history.js',
      index: ' ',
      working_dir: 'M'
    },
    FileStatusSummary {
      path: 'src-backend/api.js',
      index: ' ',
      working_dir: 'M'
    },
    FileStatusSummary {
      path: 'src/views/History.vue',
      index: ' ',
      working_dir: 'M'
    }
  ],
  staged: [ 'data/db.json' ],
  ahead: 1,
  behind: 0,
  current: 'master',
  tracking: 'origin/master'
}
```

Thanks in advance for any explanation.

### Additional contract requirements

- `git.status()` resolves to a `StatusResult` with the branch fields `current`, `tracking`, `ahead` and `behind`, the status arrays `created`, `modified`, `deleted`, `renamed`, `staged`, `not_added` and `conflicted`, a `files` array whose entries each have `path`, `index` and `working_dir`, and an `isClean()` method.
- The public function `parseStatusSummary(text: string): StatusResult` in module `src/lib/responses/StatusSummary` parses the text produced by `git status --porcelain -b -u` into that `StatusResult`.
- The public function `statusTask(customArgs: string[]): StringTask<StatusResult>` in module `src/lib/tasks/status` runs `git status --porcelain -b -u` with the supplied arguments and resolves to the result of `parseStatusSummary`.
- A file with a staged change in the index (index status `A`, `D` or `M`) is listed in `staged`; a file whose only change is in the working directory is not.
- A staged deletion (`D  <path>`) lists `<path>` in both `deleted` and `staged`; an unstaged deletion (` D <path>`) lists `<path>` only in `deleted`.
- A staged rename with unstaged modifications (`RM <from> -> <to>`) lists `{from: '<from>', to: '<to>'}` in `renamed` and `<to>` in `modified`.
- An added-then-modified entry (`AM <path>`) lists `<path>` in both `created` and `modified`.
- A malformed rename line `R  <path>` (with no `->`) lists `{from: '<path>', to: '<path>'}` in `renamed`.
