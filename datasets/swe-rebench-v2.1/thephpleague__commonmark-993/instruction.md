LinkRenderer always adding `rel="noopener noreferrer"` when opening in new window
### Version(s) affected

2.4.0

### Description

When an external link is set to open in a new window, the `noopener` and `noreferrer` values are being added, even though my config has disabled them.

### How to reproduce

Here is my setup

```php
        $config = [
            'external_link' => [
                'internal_hosts' => ['my-internal-domain.com'],
                'open_in_new_window' => true,
                'nofollow' => '',
                'noopener' => '',
                'noreferrer' => '',
            ],
        ];

        $converter = new GithubFlavoredMarkdownConverter($config);
        $converter->getEnvironment()->addExtension(new ExternalLinkExtension());

        $converter->getEnvironment()->addRenderer(FencedCode::class, new FencedCodeRenderer());
        $converter->getEnvironment()->addRenderer(IndentedCode::class, new IndentedCodeRenderer());
```

Markdown input:
```
This is an external link [Google](https://google.com/).
```

HTML output:
```
<a target="_blank" href="https://google.com/" rel="noopener noreferrer">Google</a>
```

Expected output:
```
<a target="_blank" href="https://goggle.com/">Google</a>
```
