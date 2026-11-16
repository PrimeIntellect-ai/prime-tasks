git.branch results missing some branch name
I found that git.branch does not result  some branch name

git branch -v -a

![image](https://user-images.githubusercontent.com/15901380/90329255-9cce1100-dfd5-11ea-9709-dc3be76b8cd2.png)

simple branch
```js
const simpleGit = require('simple-git');
const git = simpleGit();
git.branch().then(result => {
    console.log(result) // ==> { current: '', local: [ 'dev' ], remote: [ 'dev' ] }
})
```
The reason is because my submission contains '\r \r'

![image](https://user-images.githubusercontent.com/15901380/90329076-1c5ae080-dfd4-11ea-8031-09aa040a3b4d.png)

The Solution:

[HIDDEN]
![image](https://user-images.githubusercontent.com/15901380/90329200-1f0a0580-dfd5-11ea-9e8a-0589f0f8b42b.png)
Get current branch returns empty string
Hi, when I use `branch.current` to get the current branch name, the result is empty string sometimes.

I look into this using `DEBUG=simple-git` and found the command `git branch -v -a` it use output like this:
![image](https://user-images.githubusercontent.com/3615672/110118305-21a73d80-7df5-11eb-93fe-374d05ff2bab.png)

Whenever a `^M` in commit message, the branch info is missing,  `^M` is common to see in commit messages. (When has `\r\r`, or `\r\n`)

There is another issue about this: https://github.com/steveukx/git-js/issues/500

lib version: 2.36.0
os: window 10

### Additional contract requirements

- When a branch commit message contains a carriage return, the parsed branch's `label` must preserve that `\r` character in its original position.
- When the current branch's commit message contains a carriage return, the branch summary's `current` value must identify that branch.
