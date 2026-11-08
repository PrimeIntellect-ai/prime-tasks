List only enabled rules
As rule list is quite long already and growing I'd like a way of listing only the rules I have enabled.

It is quite impossible to spot only the enabled rules from all the all rules.

### Additional contract requirements

- Running Robocop with `--list ENABLED` prints only the rules that are enabled under the current configuration
  (including rules disabled by `--exclude`, which must be omitted). Rules that are disabled must not appear in that output.
- The same filtering keyword is accepted as the pattern of `--list` and does not match rule names as a glob.
