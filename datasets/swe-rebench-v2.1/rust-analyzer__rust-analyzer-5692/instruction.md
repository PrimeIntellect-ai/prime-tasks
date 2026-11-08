extern crate syntax not resolving
`extern crate` is still used in the 2018 edition for accessing `core`, `alloc` and `proc_macro`. Currently, the crate name after `extern crate` is not resolved, and go to def does not work on these spans.

### Additional contract requirements

- Syntax highlighting must render the crate name and alias in `extern crate` declarations as module names: render `std` as `<span class="module">std</span>` in `extern crate std;`, and render `alloc` and `abc` as `<span class="module">alloc</span>` and `<span class="module">abc</span>` in `extern crate alloc as abc;`.
