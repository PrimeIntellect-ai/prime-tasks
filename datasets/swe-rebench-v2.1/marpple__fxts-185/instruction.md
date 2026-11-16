User-Defined Type Guards not working properly in `reject` function
# Suggestion
reproduction: https://codesandbox.io/s/magical-snow-wrrz4m?file=/src/index.ts

## 💻 Use Cases
```ts
import { filter, reject, toArray } from "@fxts/core";

type ObjA = { _type: "A"; a: string; b: string };
type ObjB = { _type: "B"; a: number; b: number };

const list = [
  { _type: "A", a: "1", b: "2" },
  { _type: "B", a: 3, b: 4 },
  { _type: "A", a: "1", b: "2" },
  { _type: "B", a: 3, b: 4 }
];

const res = toArray(reject((a): a is ObjB => a._type === "B", list));

console.log(res); // `res` must be inferred to be of type `ObjA[]`
```
