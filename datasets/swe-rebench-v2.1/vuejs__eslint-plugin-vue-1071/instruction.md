no-use-v-if-with-v-for error
<!--
  Before posting the issue, please confirm that the problem you're getting
  is not related with your code editor configuration.
  To make sure it's not, run: yarn eslint src/your-file.vue
-->

**Tell us about your environment**
* **ESLint version:** 6.8.0
* **eslint-plugin-vue version:** 6.2.1
* **Node version:**	v12.16.1

**Please show your full configuration:**
<!-- Paste content of your .eslintrc file -->
```json
{
    "root": true,
    "env": {
      "node": true,
      "es6": true
    },
    "extends": [
      "plugin:vue/essential",
      "@vue/prettier"
    ],
    "rules": {
      "no-console": 0,
      "max-len": [
        "error",
        {
          "code": 120,
          "ignoreComments": true
        }
      ],
      "prettier/prettier": [
        "warn",
        {
          "printWidth": 120,
          "tabWidth": 2,
          "bracketSpacing": false
        }
      ]
    },
    "parserOptions": {
      "parser": "babel-eslint"
    }
  }
```

**What did you do?**
<!-- Please include the actual source code causing the issue. -->
As you can see I break the *no-use-v-if-with-v-for* rule, but instead to see an error, there is a execution error.
```vue
<template>
  <b-navbar-nav v-if="ready" align="center">
    <b-dropdown text="Menu"  lazy variant="lynk" size="sm">
      <!--b-dropdown-header>Dropdown header</b-dropdown-header-->
      <b-dropdown-item
        v-for="{path, name, hidden, icon, description} in userData.functions"
        v-if="!hidden"
        :key="path"
        :to="path"
      >
        <icon v-if="icon" :name="icon" /> {{ name || description || path }}
      </b-dropdown-item>
    </b-dropdown>
    <b-nav-item
      v-for="{path, name, inNav, icon, description} in userData.functions"
      v-if="inNav"
      :to="path"
      :key="path + 'Nav'"
    >
      <icon v-if="icon" :name="icon" scale="0.5" /> {{ name || description || path }}
    </b-nav-item>
  </b-navbar-nav>
</template>

<script>
import {createNamespacedHelpers} from "vuex";
const {mapState} = createNamespacedHelpers("auth");
export default {
  name: "ITDMenu",
  data() {
    return {};
  },
  computed: {
    ...mapState(["userData"]),
    ready() {
      return this?.userData?.functions?.some(el => !el.hidden);
    }
  }
};
</script>

```

**What did you expect to happen?**
I expect to see an error output.

**What actually happened?**
If I fix the error, the linter starts working again:
```vue
<template>
  <b-navbar-nav v-if="ready" align="center">
    <b-dropdown text="Menu" lazy variant="lynk" size="sm">
      <b-dropdown-item v-for="{path, name, icon, description} in functionsMenu" :key="path" :to="path">
        <icon v-if="icon" :name="icon" /> {{ name || description || path }}
      </b-dropdown-item>
    </b-dropdown>
    <b-nav-item v-for="{path, name, icon, description} in functionsNav" :to="path" :key="path + 'Nav'">
      <icon v-if="icon" :name="icon" scale="0.5" /> {{ name || description || path }}
    </b-nav-item>
  </b-navbar-nav>
</template>

<script>
import {mapState} from "vuex";
export default {
  name: "ITDMenu",
  computed: {
    ...mapState("auth", ["userData"]),
    functionsMenu() {
      return this?.userData?.functions?.filter(el => !el.hidden) || [];
    },
    functionsNav() {
      return this?.userData?.functions?.filter(el => el.inNav) || [];
    },
    ready() {
      return this?.userData?.functions?.some(el => !el.hidden);
    }
  }
};
</script>
```
<!-- Please include the actual, raw output from ESLint. -->
the actual error is:
```
± |develop U:270 ?:266 ✗| → yarn run eslint src/ITDMenu.vue
TypeError: Cannot read property 'name' of undefined
Occurred while linting /var/www/itdfw/dobleimpacto.itdmovil.cl/vue/src/ITDMenu.vue:26
    at EventEmitter.VAttribute[directive=true][key.name.name='if'] (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/eslint-plugin-vue-virtual-341ee9d370/6/home/jcmunoz/.yarn/berry/cache/eslint-plugin-vue-npm-6.2.1-a4fea6596b-2.zip/node_modules/eslint-plugin-vue/lib/rules/no-use-v-if-with-v-for.js:85:44)
    at EventEmitter.emit (events.js:323:22)
    at NodeEventGenerator.applySelector (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:3276:26)
    at NodeEventGenerator.applySelectors (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:3290:22)
    at NodeEventGenerator.enterNode (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:3298:14)
    at traverse (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:113:13)
    at traverse (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:120:21)
    at traverse (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:125:13)
    at traverse (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:120:21)
    at traverse (/var/www/itdfw/dobleimpacto.itdmovil.cl/vue/.yarn/$$virtual/vue-eslint-parser-virtual-63f41d2821/6/home/jcmunoz/.yarn/berry/cache/vue-eslint-parser-npm-7.0.0-d5f23305ab-2.zip/node_modules/vue-eslint-parser/index.js:120:21)
```

### Additional contract requirements

- When the `v-for` source is an expression and `v-if` uses an iteration variable, the diagnostic must read exactly: `The 'list()' expression inside 'v-for' directive should be replaced with a computed property that returns filtered array instead. You should not mix 'v-for' with 'v-if'.`, with the actual source expression in place of `list()`.
- When the `v-for` source is an identifier and `v-if` uses an iteration variable, the diagnostic must read exactly: `The 'list' variable inside 'v-for' directive should be replaced with a computed property that returns filtered array instead. You should not mix 'v-for' with 'v-if'.`, with the actual source identifier in place of `list`.
