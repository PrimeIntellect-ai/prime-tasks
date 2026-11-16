SyntaxError: Unexpected token svelte:head script
To reproduce try to format this snippet in any svelte file
```svelte
<svelte:head>
  <script>
    {
      "@context": "https://schema.org",
    }
  </script>
</svelte:head>
```

<img width="1057" alt="image" src="https://user-images.githubusercontent.com/49815452/173133117-19366f8e-0d27-492c-8b82-9c7fa4485076.png">

@html nested style content is being replaced with ✂prettier:content✂ + ignore not working

Hello there! I'm trying to use the `@html` template syntax to server render styles in my svelte-kit application. I have prettier auto-fix configured on save.

**My code block is as follows:**
```
<script lang="ts">
	import { getCssText } from '@stitches/core';
</script>

<svelte:head>
	{@html `<style>${getCssText()}</style>`}
	<meta name="google-site-verification" content="" />
</svelte:head>

<slot />
```

When I save the file, my code block, the code inside of `svelte:head` is altered to the following:
```
<svelte:head>
	{@html `<style ✂prettier:content✂="JHtnZXRDc3NUZXh0KCl9"></style>`}
	<meta name="google-site-verification" content="" />
</svelte:head>
```
The above issue seems to be the same as #240


I have attempted to use a prettier ignore to bypass this issue temporarily, but nothing I am trying is working and the file is still being autoformatted on save. This issue seems to be the same as #59

**I've tried the following:**
```
<svelte:head>
        <!-- prettier-ignore -->
	{@html `<style>${getCssText()}</style>`}
	<meta name="google-site-verification" content="" />
</svelte:head>
```

```
<!-- prettier-ignore -->
<svelte:head>
	{@html `<style>${getCssText()}</style>`}
	<meta name="google-site-verification" content="" />
</svelte:head>
```



**My prettier & svelte dependencies with Node 16.13.2**
```
"prettier": "^2.6.2",
"prettier-plugin-svelte": "^2.7.0",
"svelte": "^3.47.0",
```

Any insight would be much appreciated :)

### Additional contract requirements

Formatting a Svelte file must leave the content of an `{@html ...}` expression unchanged when that expression is annotated with `<!-- prettier-ignore -->`. The same directive before a `<svelte:head>` block must leave that block's content unchanged.
