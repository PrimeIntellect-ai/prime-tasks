Formatter does not work in Svelte file using TypeScript with any type annotation
## Dependency information
In a svelte file using TypeScript, when there is any type annotation within the <script> tag, the formatter does not break tailwindcss class line  properly.

## Steps to reproduce
Step1 (issue): In vscode, in an package that has `prettier-plugin-classnames` correctly setup, create a new file named `test.svelte` with following content:

```
<script lang="ts">
  let inputElement: HTMLInputElement;
</script>

<div class="relative">
  <input
    class="text-primary-700 w-full rounded-md border border-gray-300 px-3 py-2 font-semibold focus:outline-none focus:ring-2 focus:ring-blue-500"
  />
</div>
```

Execute the `Format Document` command in vscode, does not break the tailwindcss class line.

Step2 (positive control): edit the `test.svelte` file by removing the `HTMLInputElement` type annotation, now the file becomes:

```
<script lang="ts">
  let inputElement;
</script>

<div class="relative">
  <input
    class="text-primary-700 w-full rounded-md border border-gray-300 px-3 py-2 font-semibold focus:outline-none focus:ring-2 focus:ring-blue-500"
  />
</div>
```

Now execute the `Format Document` command will correctly break the class line.

## The current behavior
Step1 in reproduce section does not break class line.

## The expected behavior
Step1 in reproduce section should break class line.

I'm willing to contribute PR when we reach a proper solution. Let's use this info as a starting point for discussion. Thanks!

### Additional contract requirements

- For the reproduced fixture at `printWidth: 60`, formatting must wrap the `class` attribute when the Svelte `<script>` contains a TypeScript type annotation, for each `endingPosition` value: `absolute`, `relative`, and `absolute-with-indent`.
