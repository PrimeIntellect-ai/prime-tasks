`--svelte-bracket-new-line true` not working correctly (e.g. button and span)
`src/test.svelte`:
```svelte
<button class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r"> Copy </button>
<div class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r"> Copy </div>
<span class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r"> Copy </span>
<p class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r"> Copy </p>
```
<details>
<summary>
<code>yarn prettier --plugin-search-dir=. src/test.svelte --svelte-bracket-new-line false</code> (works fine):
</summary>

```svelte
<button
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r">
  Copy
</button>
<div
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r">
  Copy
</div>
<span
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r">
  Copy
</span>
<p
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r">
  Copy
</p>
```
</details>

`yarn prettier --plugin-search-dir=. src/test.svelte --svelte-bracket-new-line true` (some are on same line):
```svelte
<button
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r">
  Copy
</button>
<div
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r"
>Copy</div>
<span
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r">
  Copy
</span>
<p
  class="bg-green-500  text-gray-100 hover:bg-green-400 flex items-center px-4 py-2 border border-l-0 rounded-r"
>Copy</p>
```

Version:
- prettier-plugin-svelte@2.1.0
- prettier@2.2.1

Config: official template without config
