any type incorrectly generates object requirement
## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
Usage of any should not generate a type requirement and explicitly allow additional props.
```ts
 export type Test = any;
```
```json
"Test": {
    "additionalProperties": true
}
```

## Current Behavior
Currently, a type of "object" is generated. This means that only object properties are allowed.
```ts
 export type Test = any;
```
```json
"Test": {
    "additionalProperties": true,
    "type": "object"
}
```

## Detailed Description
The any (and unknown) type can by definition accept any input, therefore it does not make sense to generate a type specifier. While usage of any is generally discouraged, there are a few cases where it is useful.

For example, allowing free form JSON input for sending messages.
```ts
export interface SendMessageInput {
    topic: string;
    message: {[key: string]: any};
}
```
