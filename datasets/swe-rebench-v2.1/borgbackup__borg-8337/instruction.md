prune option keep quarterly
<!--
Thank you for reporting an issue.

*IMPORTANT* -  *before* creating a new issue please look around:
 - Borgbackup documentation: http://borgbackup.readthedocs.io/en/stable/index.html
 - FAQ: https://borgbackup.readthedocs.io/en/stable/faq.html
 and
 - open issues in Github tracker: https://github.com/borgbackup/borg/issues

If you cannot find a similar problem, then create a new issue.

Please fill in as much of the template as possible.
-->

## Have you checked borgbackup docs, FAQ, and open Github issues?

Yes

## Is this a BUG / ISSUE report or a QUESTION?

Question / Enhancement

## System information. For client/server mode post info for both machines.

#### Your borg version (borg -V).
1.1.9

#### Operating system (distribution) and version.
Debian stretch

## Describe the problem you're observing.
When using prune command, I think would be useful a retention option (`--keep-x`) between monthly and yearly, so I tought to something like `--keep-quarterly`.
Furthermore I would suggest, if it's not too complicated, a way that could make the retention policy even more customizable: use a flexible syntax like `--keep-n# number` where n is a number and # is a character in the current set (h,d,m,y). I'll make a few examples that are worth 10 explanations.
`--keep-1w` is the same as `--keep-weekly`.
`--keep-2w 3` means keep one backup every 14 days (two weeks) for a max of 3
`--keep-4m` would mean `--keep-quarterly`
`--keep-2d 5` means keep one backup every two days for a maximum of 5.
Basically the syntax is the same of the argument `--keep-within`.
Here is a simple use case. Let's say I want to backup my music folder monthly, but I don't need all the monthly backups, for example because I want to save only the big changes in my musical attitudes (switching from blues to rap let's say), then I would use `--keep-quarterly`.

Probably I wrote too much. The point is that if we use the same simple syntax used in `--keep-within` command, we could achieve a great flexibility in the retention policy.
<!--

If this complaint relates to borg performance, please include CRUD benchmark
results and any steps you took to troubleshoot.
How to run benchmark: http://borgbackup.readthedocs.io/en/stable/usage/benchmark.html

*IMPORTANT* - Please mark logs and text output from terminal commands
or else Github will not display them correctly.
An example is provided below.

Example:
```
this is an example how log text should be marked (wrap it with ```)
```
-->

### Additional contract requirements

The quarterly retention option is exposed as two mutually exclusive prune options:

- `--keep-13weekly N` — keep one archive per quarter, where a quarter is defined by the ISO 8601 week-based year (13 weeks per quarter): weeks 1–13 form the first quarter, weeks 14–26 the second, weeks 27–39 the third, and weeks 40–53 the fourth, so ISO week 53 belongs to the fourth quarter of its ISO year.
- `--keep-3monthly N` — keep one archive per quarter, where quarters are the calendar three-month periods (January–March, April–June, July–September, October–December).

Both options accept an integer count `N`, like the other `--keep-*` options, and default to 0. `N` limits how many of the most recent quarters keep an archive.
<!--

If this complaint relates to borg performance, please include CRUD benchmark
results and any steps you took to troubleshoot.
How to run benchmark: http://borgbackup.readthedocs.io/en/stable/usage/benchmark.html

*IMPORTANT* - Please mark logs and text output from terminal commands
or else Github will not display them correctly.
An example is provided below.

Example:
```
this is an example how log text should be marked (wrap it with ```)
```
-->
