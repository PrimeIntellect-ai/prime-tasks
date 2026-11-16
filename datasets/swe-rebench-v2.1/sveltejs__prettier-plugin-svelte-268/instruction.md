Style content erased
I'm seeing again the disappearing styles issue described in https://github.com/sveltejs/prettier-plugin-svelte/issues/255: in some cases, the content of the <style> tag is erased by prettier.

Repro:
```
$ npm init svelte@next my-app
Need to install the following packages:
  create-svelte@next
Ok to proceed? (y)
(...)
✔ Which Svelte app template? › Skeleton project
✔ Use TypeScript? … No
✔ Add ESLint for code linting? … No
✔ Add Prettier for code formatting? … Yes
```

At this point the dev dependencies are:
```
  "devDependencies": {
    "@sveltejs/kit": "next",
    "prettier": "^2.4.1",
    "prettier-plugin-svelte": "^2.4.0",
    "svelte": "^3.42.6"
  },
```

After npm install:
```
$ npm list
my-app@0.0.1 /Users/cr/Dora/src/my-app
├── @sveltejs/kit@1.0.0-next.196
├── prettier-plugin-svelte@2.5.0
├── prettier@2.4.1
└── svelte@3.44.1
```

I then add the following file to src/routes/test.svelte:
```
<script>
  import MyFunction from "./this_is_a_long_import_path/this_is_a_long_import_name.svelte";

  // a long, and useless comment
</script>

<style>
  iframe {
    width: 100%;
  }
</style>

<svelte:head>
  <script></script>
</svelte:head>
```

Now both `npx prettier --plugin-search-dir=. src/routes/test.svelte` or vscode `format document` will reformat the file like this, losing the style content:
```
<script>
        import MyFunction from './this_is_a_long_import_path/this_is_a_long_import_name.svelte';

        // a long, and useless comment
</script>

<svelte:head>
        <script></script>
</svelte:head>

<style></style>
```

If i downgrade prettier-plugin-svelte to 2.4.0, by removing the leading version caret in package.json, followed by npm install, I then get:
```
$ npm list
my-app@0.0.1 /Users/cr/Dora/src/my-app
├── @sveltejs/kit@1.0.0-next.196
├── prettier-plugin-svelte@2.4.0
├── prettier@2.4.1
└── svelte@3.44.1
```

And this time formatting via either the cli or vscode option works as expected.

_Originally posted by @cedricr in https://github.com/sveltejs/prettier-plugin-svelte/issues/255#issuecomment-970174634_
