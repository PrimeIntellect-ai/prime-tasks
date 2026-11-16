brace_style AlwaysNextLine fails on nightly
```toml
unstable_features = true
condense_wildcard_suffixes = true
edition = "2021"
max_width = 128
group_imports = "StdExternalCrate"
tab_spaces = 3
use_field_init_shorthand = true
use_try_shorthand = true
where_single_line = true
combine_control_expr = false
# condense_wildcard_suffixes = true
format_code_in_doc_comments = true
format_strings = true
imports_layout = "HorizontalVertical"
match_arm_blocks = false
match_block_trailing_comma = true
imports_granularity = "Crate"
reorder_impl_items = true
reorder_imports = true
reorder_modules = true
wrap_comments = true
use_small_heuristics = "Max"
trailing_comma = "Never"
brace_style = "AlwaysNextLine"
control_brace_style = "AlwaysNextLine"
```
```
error[internal]: left behind trailing whitespace
   --> /home/aspizu/Projects/onyo/src/value.rs:207:207:1
    |
207 |
    | ^^^^^^^^^
    |

error[internal]: left behind trailing whitespace
   --> /home/aspizu/Projects/onyo/src/value.rs:472:472:1
    |
472 |
    | ^^^^^^^^^
    |

warning: rustfmt has failed to format. See previous 2 errors.
```
