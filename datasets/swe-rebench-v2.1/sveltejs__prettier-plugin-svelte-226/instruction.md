prettier-ignore-start does not seem to work
**Describe the bug**
In the HTML of a Svelte file, `<!-- prettier-ignore -->` works but `<!-- prettier-ignore-start -->` does not seem to disable Prettier.

**To Reproduce**
```
<!-- prettier-ignore-->
<div class="this works this works this works this works this works this works this works this works this works" />

<!-- prettier-ignore-start -->
<div
  class="still gets formatted still gets formatted still gets formatted still gets formatted still gets formatted "
/>
<!-- prettier-ignore-end -->
```

**System (please complete the following information):**
 - OS: MacOS
 - IDE: VSCode
 - Plugin/Package: Svelte for VS Code v104.12.0
