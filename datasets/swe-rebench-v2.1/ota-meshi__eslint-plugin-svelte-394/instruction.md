`block-lang` triggers on non-svelte files
Hi
`block-lang` reports plain `.ts` files as well, no just svelte files - kind of a false positive.

I'll try to fix it, but I am not sure how to find out whether a file is a svelte file - @ota-meshi, do you just check for file extension? I can't check for `<script>` or `<style>` blocks as they theoretically may not be present...
