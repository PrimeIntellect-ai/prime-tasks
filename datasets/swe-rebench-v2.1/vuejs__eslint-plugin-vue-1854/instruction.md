`vue/require-valid-default-prop` false-positive when using TS prop definition
**Checklist**

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have read the [FAQ](https://eslint.vuejs.org/user-guide/#faq) and my problem is not listed.

**Tell us about your environment**

- **ESLint version:** 8.5.0
- **eslint-plugin-vue version:** 8.2.0
- **Node version:** 14.17.0
- **Operating System:** macOS, Ubuntu 20

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json5
require("@rushstack/eslint-patch/modern-module-resolution");

module.exports = {
    root: true,
    extends: [
        "plugin:eslint-comments/recommended",
        "plugin:vue/vue3-strongly-recommended",
        "plugin:vue/vue3-recommended",
        "airbnb-typescript/base",
        "@vue/typescript/recommended",
        "@vue/prettier",
        "plugin:storybook/recommended",
        "plugin:markdown/recommended",
        "prettier",
    ],
    plugins: ["import"],
    parserOptions: {
        ecmaVersion: 2020,
        project: ["./tsconfig.json", "./tsconfig.vite-config.json"],
    },
    settings: {
        "import/parsers": {
            "@typescript-eslint/parser": [".ts", ".tsx"],
        },
    },
    env: {
        node: true,
        es2021: true,
        "vue/setup-compiler-macros": true,
    },
    rules: {
        "@typescript-eslint/quotes": ["error", "double", { allowTemplateLiterals: true, avoidEscape: true }],
        "max-len": ["error", 200, 4],
        "no-param-reassign": "off",
        "no-use-before-define": "off",
        "no-console": "error",
        "no-debugger": "error",
        "no-plusplus": "off",
        "@typescript-eslint/no-unused-vars": "error",
        "eslint-comments/disable-enable-pair": ["error", { allowWholeFile: true }],
        "vue/no-v-html": "error",
    },
    overrides: [
        {
            files: ["vite.config.ts", "tailwind.config.js"],
            rules: {
                "import/no-extraneous-dependencies": "off",
            },
        },
    ],
};
```

**What did you do?**
```typescript
export interface SomePropInterface {
  someProp?: false | string;
}

withDefaults(defineProps<SomePropInterface>(), {
  someProp: false,
});
```

**What did you expect to happen?**

Assigning `false` to `someProp` as default value should be okay.

**What actually happened?**

`ESLint: Type of the default value for 'someProp' prop must be a string.(vue/require-valid-default-prop)`

**Repository to reproduce this issue**

I don't really think it's necessary but I will take the time to create one if really needed.
