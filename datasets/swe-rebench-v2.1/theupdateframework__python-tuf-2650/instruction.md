repository: Tweak snapshot/timestamp triggers
Currently `Repository.do_snapshot()` and `Repository.do_timestamp()` decide whether the update is needed by looking at whether the contents are up-to-date.

This bypasses one case where timestamp and snapshot are needed: when the signing keys have changed. So I guess the two methods should also check if the current snapshot/timestamp metadata is verified by root.

I did not do that originally since I was hoping the methods could be self contained and would not make assumptions about how the repository is generated/stored. This seems to be a good reason to peek at other metadata though: root should be assumed to exist and to be valid if you are calling do_snapshot/do_timestamp
