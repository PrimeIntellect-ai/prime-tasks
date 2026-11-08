[prettier-plugin-pkg] add option to ignore sorting scripts
@JounQin would you consider such an option?

In the original repo nothing happens so far 🙁 and as their repo is written JS, it is hard for me to add stuff to their repo.

https://github.com/keithamus/sort-package-json/issues/359#issuecomment-2870064069

---

here we could just allow options and allow to ignore sort scripts:

https://github.com/un-ts/prettier/blob/802cb584cc145312cd7499154b83e638b54b83aa/packages/pkg/src/index.ts#L24

might be a lot easier

and then I could switch away from `prettier-plugin-packagejson` in all my projects, even company-work

### Additional contract requirements

- The plugin accepts a `packageIgnoreSort` option, passed through Prettier's `format` call: an array of strings (default `[]`) naming top-level `package.json` fields whose contents must be excluded from the automatic sorting. Fields not listed continue to be sorted as before.
