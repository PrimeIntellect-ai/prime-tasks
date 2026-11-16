"git.log" leads (since simple-git 2.25.0) to a complete crash of the program
Since version 2.25.0 my program crashes when calling git.log without making an exception.

I wrote a mocha unit test to reproduce the bug.
The unit test passes with version 2.24.0, but crashes with version 2.25.0 without error.

```typescript
import { emptyDir, ensureDir, rmdir, writeFile } from 'fs-extra';
import { join } from 'path';
import createRepository from 'simple-git/promise';

describe('Test the git.log functionality', function () {
  it('return the parsed log entries', async function () {
    this.timeout(0);
    const testRepoPath = join(__dirname, 'test_repo_test');
    try {
      await ensureDir(testRepoPath);
      const repo = createRepository(testRepoPath);
      await repo.init();

      const commit1Path = join(testRepoPath, 'commit1');
      await writeFile(commit1Path, 'commit1');
      await repo.add(commit1Path);
      await repo.commit('Commit 1', commit1Path);
      await repo.tag(['1.0.0']);

      const commit2Path = join(testRepoPath, 'commit2');
      await writeFile(commit2Path, 'commit2');
      await repo.add(commit2Path);
      await repo.commit('Commit 2', commit2Path);

      const logs = await repo.log({
        from: 'HEAD',
        to: '1.0.0',
        symmetric: true,
      });

      console.log(logs.all);
    } finally {
      await emptyDir(testRepoPath);
      await rmdir(testRepoPath);
    }
  });
});
```

About help I would be very grateful.

### Additional contract requirements

- `git.log(options, then?)` accepts either an array of `git log` arguments or an options object, and an optional callback function.
- It returns a `Promise` that resolves with the parsed log result.
- When a callback is supplied, it is invoked with `(null, result)` on success and with `(error)` on failure.
