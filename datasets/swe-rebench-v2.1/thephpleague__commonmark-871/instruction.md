StrikethroughExtension does not work with links
### Version(s) affected

2.3.0

### Description

StrikethroughExtension does not work with links.

Input: `~~Prefix i link: https://aws.amazon.com/emr/features/hadoop/~~`
Expected output:

```
<p>
  <del>
    Prefiks i link: <a href="https://aws.amazon.com/emr/features/hadoop/">https://aws.amazon.com/emr/features/hadoop/
    </a>
  </del>
</p
```

CommonMark output:
```
<p>
  ~~Prefiks i link: https://aws.amazon.com/emr/features/hadoop/~~
</p>
```

### How to reproduce

```php
$environment = new Environment([]);
$environment->addExtension(new CommonMarkCoreExtension());
$environment->addExtension(new StrikethroughExtension());
$environment->addExtension(new AutolinkExtension());

$converter = new MarkdownConverter($environment);
$document = $converter->convert($text);

return (string) $document;
```

### Additional contract requirements

- For the reported input, preserve the exact phrase `Prefix i link:` in the rendered output; do not change it to `Prefiks i link:`.
