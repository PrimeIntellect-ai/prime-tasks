Set api won't trigger update？
here is two example about set api?
**vue2**
```
<template>
  <button @click="addA">Temp1 {{ obj.a }}</button>
</template>
<script>
export default {
  data() {
    return {
      obj: {},
    };
  },
  methods: {
    addA() {
      this.$set(this.obj, "a", "new property"); // It's work and dom update
    },
  },
};
</script>
```

**vca**
```
<template>
  <button @click="addA">Temp2 {{ obj.a }}</button>
</template>
<script>
import Vue from "vue";
import VueCompositionApi, {
  defineComponent,
  reactive,
  set,
} from "@vue/composition-api";

Vue.use(VueCompositionApi);

export default defineComponent({
  setup() {
    const obj = reactive({});
    const addA = () => {
      set(obj, "a", "new property"); // Obj change but dom not update
    };
    return {
      obj,
      addA,
    };
  },
});
</script>
```
Here is a [demo](https://codesandbox.io/s/romantic-ardinghelli-8urhp?file=/src/Temp1.vue)
