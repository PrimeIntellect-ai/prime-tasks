Parsing SDL allows `true`, `false`, and `null` for enum value names
There is a schema validator that forbids `true`, `false`, and `null` as enum value names sinde https://github.com/graphql/graphql-js/pull/812/files. The `parse` function together with the `specifiedSDLRules` rules however allow these strings to be used as enum value names/values (they're the same there). This means you can parse and successfully validate an SDL which generates a validation error when creating the schema.

I'm not quite sure whether this is a bug in the parser or a missing SDL validator. [HIDDEN] and states that the `EnumValue` non-terminal is equivalent to the `name` non-terminal:

```javascript

  /**
   * EnumValueDefinition : Description? EnumValue Directives[Const]?
   *
   * EnumValue : Name
   */
  ;

  [HIDDEN]
    var start = this._lexer.token;
    var description = this.parseDescription();
    [HIDDEN]
    var directives = this.parseDirectives(true);
    return {
      kind: Kind.ENUM_VALUE_DEFINITION,
      description: description,
      name: name,
      directives: directives,
      loc: this.loc(start)
    };
  }
```

There also is an `EnumValue` non-terminal which is defined as follows:

> EnumValue : Name but not `true`, `false` or `null`

[HIDDEN]

### Additional contract requirements

- An SDL document that uses `true`, `false`, or `null` as an enum value name must be rejected before it is accepted as valid.
