Adding custom tags
First off, thank you for this awesome package. I've been using it extensively for the last couple of months and it's been wonderful.

At my work, we label launched ec2 instances with additional tags for book-keeping purposes. Is there any interest to add that functionality to flintrock? Right now, the only tags flintrock uses are flintrock-role and Name and there's no way to append custom tags. I'm happy to take a stab if you think it's a worthwhile addition.

### Additional contract requirements

- Add a public function `validate_tags(value)` in module `flintrock.ec2`. It accepts a list of strings, each in the form `'Key,Value'` (exactly one comma). It returns a list of dictionaries, one per input entry, each of the form `{'Key': <key>, 'Value': <value>}`, in the same order as the input. Leading and trailing whitespace around the key and the value is stripped. It raises `click.BadParameter` if any entry does not contain exactly one comma, or if the key is empty after stripping whitespace.
- Add a `--ec2-tag` option to the `launch` command. The option may be given multiple times; each value is a `'Key,Value'` pair. A value that does not contain exactly one comma, or whose key is empty after stripping whitespace, is rejected.
- The tags supplied with `--ec2-tag` are attached to the EC2 instances that are launched, in addition to the tags Flintrock already applies.
