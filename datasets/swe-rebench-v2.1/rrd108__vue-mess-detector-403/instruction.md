self-closing-components incorrectly warns when an element is not alone on its line
**Describe the bug**
I have been getting warnings due to the `self-closing-components` rule on components that are empty and self-closing but are on the same line as another element.

**To Reproduce**
Here is a test case I wrote:

InsideComponent.vue
```vue
<script setup lang="ts">
  const fake = 'fake!';
</script>

<template>
  <div>{{ fake }}</div>
</template>

<style scoped>
</style>
```

VueMessTest.vue
```vue
<script setup lang="ts">
import InsideComponent from 'src/components/InsideComponent.vue';
</script>

<template>
  <a
    href="/path/to/link"
  ><InsideComponent /></a>
</template>

<style scoped>
</style>
```

Here's the command I ran and the output it gave me:
```sh
npx vue-mess-detector analyze --apply=selfClosingComponents ./src/components/VueMessTest.vue
```
```sh
Analyzing Vue, TS and JS files in ./src/components/VueMessTest.vue
👉 Using default configuration
      Project type: Vue
      Applying 0 rulesets: N/A
      Applying 1 individual rules: selfClosingComponents
      Ignoring 0 rules: N/A
      Excluding -
      Output level all
      Grouping by rule
      Sorting desc
Analyzing ./src/components/VueMessTest.vue...
Found 1 files

-  vue-strong ~ component is not self closing
   ./src/components/VueMessTest.vue
   👉 Components with no content should be self-closing. See: https://vue-mess-detector.webmania.cc/rules/vue-strong/self-closing-components.html
   line #8 <InsideComponent /></a> 🚨

Found 0 errors, and 1 warnings, 12 lines of code in 1 files
Code Health: [____________________________________________________________] 92%

Code health is OK: 92%
```

**Expected behavior**
This rule should not warn unless the element is not actually self-closing.

**Used version number of vue-mess-detector:**
```sh
$  npx vue-mess-detector -v
0.15.5
```

**Used version number of node & yarn:**
```sh
$  node -v
v22.0.0

$  npm -v
10.5.1
```
