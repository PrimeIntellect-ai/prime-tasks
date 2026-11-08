Typescript error with functional component
Hi,

I have an error by defining a functional component in Typescript with the composition api:

```javascript
import { defineComponent } from '@vue/composition-api';

export default defineComponent({
  functional: true,
});
```

```
Error:(14, 3) TS2769: No overload matches this call.
  Overload 1 of 3, '(options: ComponentOptionsWithoutProps<unknown, unknown, Data, {}, {}>): VueProxy<unknown, unknown, Data, {}, {}>', gave the following error.
    Argument of type '{ functional: boolean; }' is not assignable to parameter of type 'ComponentOptionsWithoutProps<unknown, unknown, Data, {}, {}>'.
      Object literal may only specify known properties, and 'functional' does not exist in type 'ComponentOptionsWithoutProps<unknown, unknown, Data, {}, {}>'.
  Overload 2 of 3, '(options: ComponentOptionsWithArrayProps<string, Data, Data, {}, {}, Readonly<{ [x: string]: any; }>>): VueProxy<Readonly<{ [x: string]: any; }>, Data, Data, {}, {}>', gave the following error.
    Argument of type '{ functional: boolean; }' is not assignable to parameter of type 'ComponentOptionsWithArrayProps<string, Data, Data, {}, {}, Readonly<{ [x: string]: any; }>>'.
      Object literal may only specify known properties, and 'functional' does not exist in type 'ComponentOptionsWithArrayProps<string, Data, Data, {}, {}, Readonly<{ [x: string]: any; }>>'.
  Overload 3 of 3, '(options: ComponentOptionsWithProps<ComponentPropsOptions<Data>, Data, Data, {}, {}, ({ [x: number]: string; } & { toString?: string; toLocaleString?: string; concat?: string[]; indexOf?: (searchElement: string, fromIndex?: number) => number; ... 25 more ...; values?: IterableIterator<...>; }) | ({} & { ...; })>): VueProxy<...>', gave the following error.
    Argument of type '{ functional: boolean; }' is not assignable to parameter of type 'ComponentOptionsWithProps<ComponentPropsOptions<Data>, Data, Data, {}, {}, ({ [x: number]: string; } & { toString?: string; toLocaleString?: string; concat?: string[]; indexOf?: (searchElement: string, fromIndex?: number) => number; ... 25 more ...; values?: IterableIterator<...>; }) | ({} & { ...; })>'.
      Object literal may only specify known properties, and 'functional' does not exist in type 'ComponentOptionsWithProps<ComponentPropsOptions<Data>, Data, Data, {}, {}, ({ [x: number]: string; } & { toString?: string; toLocaleString?: string; concat?: string[]; indexOf?: (searchElement: string, fromIndex?: number) => number; ... 25 more ...; values?: IterableIterator<...>; }) | ({} & { ...; })>'.
```


The same code works on Vue 3.

### Additional contract requirements

- `defineComponent` accepts an options object that contains arbitrary additional custom keys of any name and type, without producing a TypeScript error.
