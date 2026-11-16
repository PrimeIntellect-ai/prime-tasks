FR: Add option to save YAML timestamps in UTC
I'm currently using my Obsidian vault in conjunction with external tooling (TiddlyWiki) that expects the created & modified YAML frontmatter datetimes to always be in UTC. Adding an option to save YAML timestamps in UTC allows Linter's timestamps to be interoperable with TiddlyWiki and other external tools that might only be able to work with UTC.

I'd like the option to choose whether or not local times are converted to UTC times before being formatted & saved in created / modified frontmatter. For my specific use case, a boolean option is sufficient.

For example, if a file was created at 9 PM Eastern Standard Time on Jan 1st 2020 and convertToUTC was true, the file's _date created_ value would be 2 AM Jan 2nd 2020 in UTC.

Local time:
``` markdown
---
date created: 2020-01-01T21:00:00-05:00
---
```
Converted to UTC:
``` markdown
---
date created: 2020-01-02T02:00:00+00:00
---
```

Re: possible alternative solutions - I've attempted to modify TiddlyWiki to work with non-UTC time stamps and it's not feasible for me at this time. This also seems outside the scope of a change that would make sense for Obsidian's core. Adding to Linter makes the most sense to me for wider compatibility.
