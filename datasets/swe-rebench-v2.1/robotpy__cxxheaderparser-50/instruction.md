[BUG]: anonyous structs and unions are not added to class fields
### Problem description

When using the simple.py anonymous unions are not added to class fields. In my view they sould be added since they are also class embers and contribute to the object size. For each anonimous union a field with no name should be added to class fields.

### Operating System

Windows

### Installed Python Packages

_No response_

### Reproducible example code

```text
// when parsing this only member and member2 are added to example_class fields.
class example_class {
    int member;
    union {
        std::uint32_t a;
        std::uint16_t b[2];
    };
    int member2;
};
```

### Additional contract requirements

Each anonymous struct or union declared within a class must appear in that class's fields as a field without a name. This applies to every such declaration in the class.
