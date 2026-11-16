camel-case commands
For options, e.g., `--foo-bar`, we populate the camel-case `fooBar` variable on the argv object. For commands we're not that clever:

`.command('foo <api-token>')` will result in only `api-token` being populated on the argv object; it would be nice if we were clever enough to populate both `api-token` and `apiToken`.
