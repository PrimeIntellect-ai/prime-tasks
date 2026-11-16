disclosure

### Additional contract requirements

Add a public function component `Doggo.disclosure_button/1` in the module `Doggo` that renders a `<button>` element with `type="button"`, `aria-expanded="false"`, and `aria-controls` set to the provided `:controls` value. The `:controls` input is a required string. The `:inner_block` slot is required and supplies the button's label or content.
