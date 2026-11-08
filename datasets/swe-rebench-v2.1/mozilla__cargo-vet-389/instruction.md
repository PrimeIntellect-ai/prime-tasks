Imports should drop audits with unkown fields
Currently the import machinery silently drops audit fields it doesn't understand. This creates a risk that we might add some future audit field that serves as a caveat (only these features, only these targets, etc), and a consumer on an older version ends up with a more sweeping audit than the author intended. We should change the behavior so that an unknown field causes the entire entry to be dropped.

A downside of this change is that it would no longer be possible for projects to rewrite existing audits with new fields without potentially breaking consumers on older versions. However, this would merely result in the consumer getting some errors and deciding to upgrade, whereas the current situation risks unsoundness.

I _think_ we should do the same for all the tables (including audits and wildcards), but I haven't fully thought those through.
