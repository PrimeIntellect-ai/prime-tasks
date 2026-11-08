Extra trailing space in else branch of a conditional type
**Describe the bug**

Extra trailing space after ":" is inserted when formatting a conditional type + intersection type

dprint-plugin-typescript version: 0.84.1

**Input Code**

```ts
type Type<T = any> = T extends never ? never
    : // <--- here!
        & { ephemeral?: T }
        & (
            | Object_Type
            | Union_Type
            | Intersection_Type
            | Enum_Member_Type
            | Generic_Type
            | Primitive
            | Enum_Type
            | Array_Type
            | Tuple_Type
            | Any_Type
            | Custom_Type
        )
    ;
```

**Expected Output**

```ts
type Type<T = any> = T extends never ? never
  // <--- here!
  :
    & { ephemeral?: T }
    & (
      | Object_Type
      | Union_Type
      | Intersection_Type
      | Enum_Member_Type
      | Generic_Type
      | Primitive
      | Enum_Type
      | Array_Type
      | Tuple_Type
      | Any_Type
      | Custom_Type
    );

```

**Actual Output**

```ts
type Type<T = any> = T extends never ? never
  // <--- here!
  :
    & { ephemeral?: T }
    & (
      | Object_Type
      | Union_Type
      | Intersection_Type
      | Enum_Member_Type
      | Generic_Type
      | Primitive
      | Enum_Type
      | Array_Type
      | Tuple_Type
      | Any_Type
      | Custom_Type
    );
```
