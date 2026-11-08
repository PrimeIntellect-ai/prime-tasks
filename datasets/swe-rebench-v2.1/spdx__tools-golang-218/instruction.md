Check for duplicates when unmarshaling shortcut fields
In PR https://github.com/spdx/tools-golang/pull/201, we introduced the auto unparsing of the shortcut "documentDescribes" and "hasFiles" fields.

It doesn't seem that in the code that this checks for duplicates, and may result in duplicate relationships.

Reported on behalf on Google internal user (Amit).
