Unnecessary warnings when command flags are marked as deprecated
**Is your feature request related to a problem? Please describe.**
I noticed that there was an [update](https://github.com/oclif/core/pull/511/) with version 1.18.0 to show that commands or flags are deprecated. I attempted to use this new feature with certain flags that are part of my application, but ran into what feels like a UX issue. With this update, no matter what flags are actually used, warnings about all of the deprecated flags of a command will be printed.

For example, [this test](https://github.com/oclif/core/pull/511/files#diff-e63382cfea41aa63be2c32caf2d9f0a840fa54e40a9d4898a9c3f0b4c6f7919fR236) shows that the flag `name` is deprecated. However, even though the command is run with no flags, a warning about the deprecated command is expected to be printed.

This situation could produce a lot of spam and be confusing for the user, especially if there are many deprecated flags in the command class none of which the user included in the actual command.

**Describe the solution you'd like**
The logic for deprecated flags should only print a warning for the deprecated command(s) that a user actually used. If I used two out of four deprecated flags, I'd expect two warnings. If I didn't use any deprecated commands, I'd expect no warnings.
