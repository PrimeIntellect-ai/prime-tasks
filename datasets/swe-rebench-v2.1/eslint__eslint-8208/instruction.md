npm install not working.
**Tell us about your environment**

* **ESLint Version:** master
* **Node Version:** 7.6.0
* **npm Version:** 4.2.0

**What parser (default, Babel-ESLint, etc.) are you using?**

- default

**Please show your full configuration:**

- nothing

**What did you do? Please include the actual source code causing the issue.**

`npm install` in ESLint repo.

**What did you expect to happen?**

`npm install` completes normally.

**What actually happened? Please include the actual, raw output from ESLint.**

`npm install` failed.


```
~\Documents\GitHub\eslint [no-extra-parens/spread-operators]> npm install
npm WARN addRemoteGit Error: Command failed: git -c core.longpaths=true config --get remote.origin.url
npm WARN addRemoteGit
npm WARN addRemoteGit     at ChildProcess.exithandler (child_process.js:211:12)
npm WARN addRemoteGit     at emitTwo (events.js:106:13)
npm WARN addRemoteGit     at ChildProcess.emit (events.js:192:7)
npm WARN addRemoteGit     at maybeClose (internal/child_process.js:890:16)
npm WARN addRemoteGit     at Socket.<anonymous> (internal/child_process.js:334:11)
npm WARN addRemoteGit     at emitOne (events.js:96:13)
npm WARN addRemoteGit     at Socket.emit (events.js:189:7)
npm WARN addRemoteGit     at Pipe._handle.close [as _onclose] (net.js:501:12)
npm WARN addRemoteGit  git://github.com/not-an-aardvark/mock-fs/#06868bbd7724707f9324b237bdde28f05f7a01d5 resetting remote C:\Users\t-nagashima.AD\AppData\Roami
ng\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237bdde28f05f7a01d5-cdc216ca because of error: { Error: Command failed: gi
t -c core.longpaths=true config --get remote.origin.url
npm WARN addRemoteGit
npm WARN addRemoteGit     at ChildProcess.exithandler (child_process.js:211:12)
npm WARN addRemoteGit     at emitTwo (events.js:106:13)
npm WARN addRemoteGit     at ChildProcess.emit (events.js:192:7)
npm WARN addRemoteGit     at maybeClose (internal/child_process.js:890:16)
npm WARN addRemoteGit     at Socket.<anonymous> (internal/child_process.js:334:11)
npm WARN addRemoteGit     at emitOne (events.js:96:13)
npm WARN addRemoteGit     at Socket.emit (events.js:189:7)
npm WARN addRemoteGit     at Pipe._handle.close [as _onclose] (net.js:501:12)
npm WARN addRemoteGit   killed: false,
npm WARN addRemoteGit   code: 1,
npm WARN addRemoteGit   signal: null,
npm WARN addRemoteGit   cmd: 'git -c core.longpaths=true config --get remote.origin.url' }
npm ERR! git clone --template=C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\_templates --mirror git://github.com/not-an-aardvark/mock-fs/ C:\Us
ers\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237bdde28f05f7a01d5-cdc216ca: Cloning into
 bare repository 'C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237bdde28f05f7a01d5
-cdc216ca'...
npm ERR! git clone --template=C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\_templates --mirror git://github.com/not-an-aardvark/mock-fs/ C:\Us
ers\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237bdde28f05f7a01d5-cdc216ca: fatal: unabl
e to connect to github.com:
npm ERR! git clone --template=C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\_templates --mirror git://github.com/not-an-aardvark/mock-fs/ C:\Us
ers\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237bdde28f05f7a01d5-cdc216ca: github.com[0
: 192.30.253.113]: errno=No error
npm ERR! git clone --template=C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\_templates --mirror git://github.com/not-an-aardvark/mock-fs/ C:\Us
ers\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237bdde28f05f7a01d5-cdc216ca: github.com[1
: 192.30.253.112]: errno=No error
npm ERR! Windows_NT 6.1.7601
npm ERR! argv "C:\\Users\\t-nagashima.AD\\nodist\\v-x64\\nodev7.6.0\\node.exe" "C:\\Users\\t-nagashima.AD\\nodist\\bin\\node_modules\\npm\\bin\\npm-cli.js" "ins
tall"
npm ERR! node v7.6.0
npm ERR! npm  v4.2.0
npm ERR! code 128

npm ERR! Command failed: git -c core.longpaths=true clone --template=C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\_templates --mirror git://gi
thub.com/not-an-aardvark/mock-fs/ C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f9324b237
bdde28f05f7a01d5-cdc216ca
npm ERR! Cloning into bare repository 'C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_git-remotes\git-github-com-not-an-aardvark-mock-fs-06868bbd7724707f932
4b237bdde28f05f7a01d5-cdc216ca'...
npm ERR! fatal: unable to connect to github.com:
npm ERR! github.com[0: 192.30.253.113]: errno=No error
npm ERR! github.com[1: 192.30.253.112]: errno=No error
npm ERR!
npm ERR!
npm ERR!
npm ERR! If you need help, you may report this error at:
npm ERR!     <https://github.com/npm/npm/issues>

npm ERR! Please include the following file with any support request:
npm ERR!     C:\Users\t-nagashima.AD\AppData\Roaming\npm-cache\_logs\2017-03-06T22_06_08_590Z-debug.log
```
