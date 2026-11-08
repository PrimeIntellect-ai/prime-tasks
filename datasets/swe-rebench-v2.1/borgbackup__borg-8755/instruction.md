remote repository exceptions give classic (not modern) result codes
<!--
Thank you for reporting an issue.

*IMPORTANT* -  *before* creating a new issue please look around:
 - Borgbackup documentation: http://borgbackup.readthedocs.io/en/stable/index.html
 - FAQ: https://borgbackup.readthedocs.io/en/stable/faq.html
 and
 - open issues in GitHub tracker: https://github.com/borgbackup/borg/issues

If you cannot find a similar problem, then create a new issue.

Please fill in as much of the template as possible.
-->

## Have you checked borgbackup docs, FAQ, and open GitHub issues?

Yes

## Is this a BUG / ISSUE report or a QUESTION?

ISSUE

## System information. For client/server mode post info for both machines.

#### Your borg version (borg -V).
1.4.0 on server and client

#### Operating system (distribution) and version.
Client:
Distributor ID:	Debian
Description:	Debian GNU/Linux 12 (bookworm)
Release:	12
Codename:	bookworm

Server: borgbase


#### Full borg commandline that lead to the problem (leave away excludes and passwords)

```
borg create --info --stats --compression=auto,zstd,9 --files-cache=ctime,size,inode --show-rc ssh://testrepo_borgbase/./repo_modern_rc::daily-20250111 /path/to/myfilestobackup
```
## Describe the problem you're observing.

I'm writing some wrapper scripts for borg. I want to rely on the return codes of borg with the modern BORG_EXIT_CODES, to trigger the init of repo, if it doesn't exist.
I've exported the BORG_EXIT_CODES=modern variable.
But when I try to execute above command line, I'll get rc 2 instead of rc 15
```
is not a valid repository. Check repo config.
terminating with error status, rc 2
```
#### Can you reproduce the problem? If so, describe how. If not, describe troubleshooting steps you took before opening the issue.

If I do the same with a local existing path without repository, I'll get rc 15
```
borg create --info --stats --compression=auto,zstd,9 --files-cache=ctime,size,inode --show-rc /home/borg/test_repo_rc::daily-20250111  /path/to/myfilestobackup
/home/borg/test_repo_rc is not a valid repository. Check repo config.
terminating with error status, rc 15
```
I've did the same test with a remote server at Hetzner.

```
borg create --info --stats --compression=auto,zstd,9 --files-cache=ctime,size,inode --show-rc --remote-path=borg ssh://borg_hetzner_sub2/home/test_repo_rc::daily-20250111 /path/to/myfilestobackup
```
I'll get rc 2, too.

When I try to create the repo on a directory which doesn't exist I'll get rc 13 on the remote Hetzner box. Which I would expect.

My assumption is, that the handling for invalid repository error code some how differs between local and remote repos


<!--

If this complaint relates to borg performance, please include CRUD benchmark
results and any steps you took to troubleshoot.
How to run benchmark: http://borgbackup.readthedocs.io/en/stable/usage/benchmark.html

*IMPORTANT* - Please mark logs and text output from terminal commands
or else GitHub will not display them correctly.
An example is provided below.

Example:
```
this is an example how log text should be marked (wrap it with ```)
```
-->
