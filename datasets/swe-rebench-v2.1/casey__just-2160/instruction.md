It should be possible to have groups appear in justfile order
`just` supports outputting individual commands in the order they are defined in the justfile:

> `just --list --unsorted` prints recipes in their justfile order within each group:
>
> https://github.com/casey/just?tab=readme-ov-file#recipe-groups

However, the `--unsorted` flag does not appear to apply to the groups themselves, neither can I see an option to have the groups printed in justfile order.

### Additional contract requirements

`just --groups --unsorted` prints the recipe groups in justfile order, and `just --groups` without `--unsorted` prints them in alphabetical order. Each group name is printed once.


- For `--groups` output, print `Recipe groups:` as the header and prefix each group name with four spaces.
- Only groups associated with public recipes are printed.
