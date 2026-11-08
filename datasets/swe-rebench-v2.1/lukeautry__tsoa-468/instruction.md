Empty string in Enum got converted to '0'
When using empty string `''` in string Enum used a input parameter, it got converted as `'0'`.

So imagine an enum like:

```ts
export enum MyThings {
    Undefined = '',
    Something = 'Something',
    Otherwise = 'Another Something',
```

## Sorting

* **I'm submitting a ...**
  - [X] bug report

* I confirm that I
  - [X] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior

I would expect that the empty string is returned in the swagger doc.

```yaml
    "MyThings ": {
        "enum": [
            "",
            "Something",
            "Another Something"
        ],
        "type": "string"
    },
```

And the '' value should be accepted during data validation.

## Current Behavior
But I got that in swagger config and for validation:

```yaml
    "MyThings ": {
        "enum": [
            "0",
            "Something",
            "Another Something"
        ],
        "type": "string"
    },
```

Well it's 0 because it's in first position, but moving it elsewhere, it will take the index of the position:

```yaml
    "MyThings ": {
        "enum": [
            "Something",
            "Another Something",
            "2"
        ],
        "type": "string"
    },
```

Trying to pass empty string as the value to end point, I got the error "Should be one of [0, Something, Another Something]"

## Workaround
You can change the empty string for something else, like a single space, dash or the word 'Undefined'. But this break Boolean conversion and seems counter-intuitive.

## Context (Environment)
Version of the library: 2.3.8 & 2.4.11
Version of NodeJS: 10.14.1
* Confirm you were using yarn not npm: [X]

## Detailed Description
<!--- Provide a detailed description of the change or addition you are proposing -->

## Breaking change?
This change the current behaviour, so it's a breaking change in principle. But this seems unlikely that anyone have used empty string in enum as it is.
