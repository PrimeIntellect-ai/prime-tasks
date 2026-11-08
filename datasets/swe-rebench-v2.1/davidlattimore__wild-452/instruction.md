Add support for --whole-archive
See `man ld` for a description of what `--whole-archive` needs to do.

`--whole-archive` is a modifier that is pushed / popped by `--push-state` / `--pop-state`, [HIDDEN]

It'd be good to have a test that verifies that `--whole-archive` is behaving as expected. There are probably a few ways such a test could be written. The key observation is that whatever is defined in the archive needs to not be directly referenced from the main test object, otherwise the archived object would be included even without `--whole-archive`. One option is to have an archive that puts something into a custom section, then have the `_start_` function check the custom section for that value. You can look at the test `custom_section.c` for how this is done.

### Additional contract requirements

- Support `--no-whole-archive` to disable whole-archive behavior for subsequent archive inputs, so archive members are included only when needed to resolve references.
