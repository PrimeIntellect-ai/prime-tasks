`magicNumbers` rule should skip comments matches
**Describe the bug**
The analyzer is detecting some numbers in comments lines (e.g ui/issues/**1289**) as magic numbers

**To Reproduce**
Run the analyzer in this code:
```js
export default defineAppConfig({
  ui: {
    primary: 'blue',
    gray: 'cool',
  },
  nuxtIcon: {}, // see https://github.com/nuxt/ui/issues/1289 and https://github.com/nuxt/ui/pull/1789
})
```

1. What is the exact code you are analyzing?
The code from above ⬆️

2. What is the output you are getting?
![image](https://github.com/user-attachments/assets/14e2042d-3139-4953-a2d3-a5e2a11878cb)

**Expected behavior**
It should ignore comments

**Screenshots**
N/A

**Used version number of vue-mess-detector:** `latest`

**Used version number of node & yarn:** `-`

**Additional context**
Reported via [Discord Server Help Channel](https://discord.com/channels/1280952778734305410/1281720249653395467/1290722684472266904)
