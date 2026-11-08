Sort out S3Path.toString() behaviour
# Task Description

The implementation of `S3Path.toString()` is returning the URI (for this we already have the `toURI()` method). AFAIK the implementation of `Path.toString()` for Linux/Windows file system doesn't add the scheme (`file:///`). I think the `S3Path` should follow that approach. Other concern is that the creation of a `S3Path` uses a `bucket` + `key`, and if the `toString` returns more than that, we cannot create a `S3Path` using that (yes, there are ways to do that, but I prefer to keep it simple if possible). Hope this helps!

# Tasks

The following tasks will need to be carried out:
* [ ] Investigate the issue.
* [ ] Implement a fix.
* [ ] Test.

# Task Relationships

This task:
* Is a sub-task of: #
* Depends on: #
* Is a follow-up of: #
* Relates to: #

# Useful Links


# Help

* Points of contact:
  * @carlspring
  * @steve-todorov
