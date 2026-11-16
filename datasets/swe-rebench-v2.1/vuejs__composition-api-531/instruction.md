Warnings In Tests When Using createLocalVue() From vue-test-utils
When using any of the 1.0.0 betas, a lot of warnings get printed during tests. This is caused by code like this:

```ts
import VueCompositionAPI from "@vue/composition-api";
import { createLocalVue } from "@vue/test-utils";
import range from "lodash/range";
import { VueConstructor } from "vue";

describe("warnings", () => {
  let localVue: VueConstructor;

  beforeEach(() => {
    localVue = createLocalVue();
    localVue.use(VueCompositionAPI);
  });

  test.each(range(5))("create localVue 5 times", () => {
    expect(localVue).toBeDefined();
  });
});

```
The printed warning will look like this:
```
 [Vue warn]: Another instance of vue installed
```

Is there anything that could be done to silence those warnings? The issue seems to be related to https://github.com/vuejs/composition-api/issues/492

### Additional contract requirements

- Installing the plugin into multiple local Vue constructors created from the same base Vue constructor (for example, several `createLocalVue()` instances) must not emit the “Another instance of vue installed” warning.
- Installing the plugin into a Vue constructor that is not derived from the already‑registered constructor (for example, the minimal mock object described in the interface) emits the “Another instance of vue installed” warning.
- Installing the plugin again for a Vue constructor that already has it installed throws an error with the message: “already installed. Vue.use(VueCompositionAPI) should be called only once.”
