Sphinx-Needs throws exception when "." is used in ID
Sphinx-Needs throws a cryptic python error

> Extension error (sphinx_needs.directives.need):
Handler <function process_need_nodes at 0x7fc668dc98a0> for event 'doctree-resolved' threw an exception (exception: too many values to unpack (expected 2))

if "." is used in an ID after configuring a regex as follows in `conf.py`

> needs_id_regex = r'.*'

Although it is not a good idea to use "." in IDs, Sphinx-Needs should be robust with such a case.

Related Issue: https://github.com/useblocks/sphinx-needs/issues/852

### Additional contract requirements

- When `needs_id_regex` permits periods in need IDs, a need whose ID contains a period (including IDs with more than one period) and that is referenced from another need through a link option must not cause the build to raise an exception.
