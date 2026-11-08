Default column name to pojo field name, and add `allFields` mode to `Measurement` annotation
It would be nice if `@Column` could be used without a name, in which case the field name would be used as the column name.

In addition, when a pojo has many fields, it would be nice to be able to annotate it with `@Measurement(name = "...", allFields = true)` instead of annotating every field with `@Column`.
Finally, an `@Exclude` annotation on fields would be helpful, for opting a field out in this mode.

I have implemented such support. Should I submit a PR?
