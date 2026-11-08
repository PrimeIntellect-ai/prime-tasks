Bug: In No Bare URLs, Percent-Encoding in URLs to be formatted incorrectly.
- [X] I have verified that I am on the latest version of the Linter

Version: 1.23.1

## Describe the Bug

The percent sign is a legal charater in URI, but after formatting, the percent sign is placed outside of the Angle brackets.

>    A percent-encoding mechanism is used to represent a data octet in a
   component when that octet's corresponding character is outside the
   allowed set or is being used as a delimiter of, or within, the
   component. [^1]

[^1]: RFC 3986 - Uniform Resource Identifier (URI): Generic Syntax: https://datatracker.ietf.org/doc/html/rfc3986#section-2.1

## How to Reproduce

Enable No Bare URLs.

Original sentence

```markdown
https://zh.wikipedia.org/wiki/%E5%85%AC%E5%8E%86
https://baike.baidu.com/item/%E7%99%BE%E7%A7%91
https://www.google.com/search?q=%E7%A9%BA%E6%A0%BC
https://cn.bing.com/search?pglt=163&q=%E6%A0%BC%E5%BC%8F%E5%8C%96
https://www.google.com/search?q=%E3%81%A1%E3%82%85%E3%81%86%E3%81%94%E3%81%8F%E3%81%94
```

After formatting

```markdown
<https://zh.wikipedia.org/wiki/>%E5%85%AC%E5%8E%86
<https://baike.baidu.com/item/>%E7%99%BE%E7%A7%91
# Here the equal sign is also excluded.
<https://www.google.com/search?q>=%E7%A9%BA%E6%A0%BC
<https://cn.bing.com/search?pglt=163&q>=%E6%A0%BC%E5%BC%8F%E5%8C%96
<https://www.google.com/search?q>=%E3%81%A1%E3%82%85%E3%81%86%E3%81%94%E3%81%8F%E3%81%94
```

But the correct result should be


```markdown
<https://zh.wikipedia.org/wiki/%E5%85%AC%E5%8E%86>
<https://baike.baidu.com/item/%E7%99%BE%E7%A7%91>
<https://www.google.com/search?q=%E7%A9%BA%E6%A0%BC>
<https://cn.bing.com/search?pglt=163&q=%E6%A0%BC%E5%BC%8F%E5%8C%96>
<https://www.google.com/search?q=%E3%81%A1%E3%82%85%E3%81%86%E3%81%94%E3%81%8F%E3%81%94>
```

## Screenshots

![01](https://github.com/platers/obsidian-linter/assets/61381278/e0e3d8c0-48cb-4b40-b1f3-1d9787f3f014)

## Device

- [X] Desktop
- [ ] Mobile

## Additional Context

May be related to: #900
