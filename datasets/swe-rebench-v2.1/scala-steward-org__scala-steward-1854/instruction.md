git fetch --tags fails with 'rejected (would clobber existing tag)'
Just noticed this error in the logs of my public instance:
```
2020-12-31 12:14:44,738 INFO  ──────────── Steward augustjune/canoe ────────────
2020-12-31 12:14:44,738 INFO  Check cache of augustjune/canoe
2020-12-31 12:14:45,139 INFO  Clone and synchronize augustjune/canoe
2020-12-31 12:14:48,650 ERROR Steward augustjune/canoe failed
java.io.IOException: '... git fetch --tags upstream master' exited with code 1
From https://github.com/augustjune/canoe
 * branch            master     -> FETCH_HEAD
 ! [rejected]        v0.0.2     -> v0.0.2  (would clobber existing tag)
 * [new tag]         v0.0.3     -> v0.0.3
 * [new tag]         v0.0.4     -> v0.0.4
 * [new tag]         v0.0.5     -> v0.0.5
 * [new tag]         v0.1.0     -> v0.1.0
 * [new tag]         v0.1.1     -> v0.1.1
 * [new tag]         v0.1.2     -> v0.1.2
 * [new tag]         v0.2.0     -> v0.2.0
 * [new tag]         v0.3.0     -> v0.3.0
 * [new tag]         v0.3.1     -> v0.3.1
 * [new tag]         v0.4.0     -> v0.4.0
 * [new tag]         v0.4.1     -> v0.4.1
 * [new tag]         v0.5.0     -> v0.5.0
 * [new tag]         v0.5.0-RC1 -> v0.5.0-RC1
 * [new tag]         v0.5.1     -> v0.5.1
 * [new branch]      master     -> upstream/master
```
The `v0.0.2` tag is causing trouble: ` ! [rejected]        v0.0.2     -> v0.0.2  (would clobber existing tag)`. Probably because it has been deleted and recreated in the upstream repo.
