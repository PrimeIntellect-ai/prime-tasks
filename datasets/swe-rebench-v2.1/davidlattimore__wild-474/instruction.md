Incorrect string-merge results -mcmodel=large is used with clang
When `program_name_29___cpp_integration_cc__` is compiled with `clang` rather than `gcc`, it fails. Apparently all the merged strings end up as the string `ELF`. See https://github.com/davidlattimore/wild/pull/140. We should probably first add an option to allow overriding the compiler - i.e. #179.
