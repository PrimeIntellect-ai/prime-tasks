Bug: Header increment breaks when tags are used in the header
## Describe the Bug
In a document with properly-incremented headers, when a tag (i.e. `#`) is added onto one of the headers, the sub-headers gets bumped up to the same level as the header with the tag.

## How to Reproduce

Example to reproduce issue with

``` markdown
# Page Title
## Foo #tag
### Bar
### Baz
```

Linter Config for incrementing header:
```
 "Header Increment": {
      "Heading levels should only increment by one level at a time": true,
      "Start Header Increment at Heading Level 2": false
    },
```

## Expected Behavior

Expected output:


``` markdown
# Page Title
## Foo #tag
### Bar
### Baz
```

The actual output:

``` markdown
# Page Title
## Foo #tag
## Bar
## Baz
```

## Device

- [x] Desktop
- [ ] Mobile

Reproducible in both v1.10.1 and v1.10.2
Bug: Header capitalization capitalizes words after words that contain numbers
## Describe the Bug

When header capitalization is selected ("first letter" style) and there's an acronym or word that contains a number the next word will be capitalized

## How to Reproduce

Examples to reproduce issue with

``` markdown
# EC2 instance
## EC2 lab05 load balancer
### lab07 bread maker
```

The result of the above markdown is:

```markdown
# EC2 Instance

## EC2 lab05 Load balancer

### lab07 Bread maker
```

(Instance, Load, and Bread are incorrectly capitalized)


Expected output if applicable:

``` markdown
# EC2 instance

## EC2 lab05 load balancer

### Lab07 bread maker
```

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

- [x] Desktop
- [ ] Mobile
