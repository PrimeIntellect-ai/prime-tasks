Auto fix of `vue/attribute-hyphenation` rule cause error on passing props to child component
<!--
  ❗Please don't ignore this template.❗

  If you ignore it, we're just going to respond asking you to fill it out, which wastes everyone's time.
  The more relevant information you can include, the faster we can find the issue and fix it without asking you for more info.
-->

<!--
  Before posting the issue, please confirm that the problem you're getting
  is not related with your code editor configuration.
  To make sure it's not, run: yarn eslint src/your-file.vue
-->

**Checklist**

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have read the [FAQ](https://eslint.vuejs.org/user-guide/#faq) and my problem is not listed.
<!-- If you do not read the FAQ and open an issue that is listed in the FAQ, we may silently close the issue. -->

**Tell us about your environment**

- **ESLint version:** ^8.15.0
- **eslint-plugin-vue version:** 9.15.1
- **Node version:** 16.20.1
- **Operating System:** Linux Ubuntu

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json5
{
  rules: {
    "vue/attribute-hyphenation": "error"
  }
}
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->

[link to reproduction](https://play.vuejs.org/#eNqFUstOwzAQ/BVrL72URNBbFZCg6gEkoAJumEOUbFsXx7b8KEFV/h0/lFBE1N52d2ad2cwc4FapbO8Q5lCYSjNliUHr1A0VrFFSW7LYMl6TtZYNmWR57MLChIoiTxue6xuLjeKlRd8RUtRsHwtfxpVUE/L4vdJSXVO4pJBm+Siv6XlX53gXKhFnf4lFniQU+SAMpmBNJcWabbKdkcLffAhUCpVsFOOon5VlUhgKcxKRgJWcy6+HOLPa4bSfV1usPkfmO9OGGYWVRoN6jxQGzJZ6gzbBy9cnbH09gI2sHffsE+ALGsld0Jhod07UXvYRL6q9j84xsXkzy9aiMP1RQWhgdpFPwfu4OHH6r9xZNot7VHT+Lw4hCKn573vy2L9zSFXXjZgRMzPkB9uYtRrXpeM2KQi+mjl5p5CeofDhP38UO+h+AM4045U=)

**What did you expect to happen?**

Do not auto fix attribute name

**What actually happened?**
<!--
  Please include the actual, raw output from ESLint.
  If you are only looking at the results of your editor extension, also check the CLI results.
-->

Fixer changed property name, what caused incorrect data passing to child component

**Repository to reproduce this issue**
<!--
  ❗ Please share a repository that can reproduce your issue.
  ❗ If you don't share it, we just label it as requesting a repository that can reproduce your issue.
  ❗ If you don't share it for a few days, we silently close this issue.
-->

Link above ^
