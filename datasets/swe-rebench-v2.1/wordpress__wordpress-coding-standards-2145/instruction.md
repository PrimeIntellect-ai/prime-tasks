Add antispambot to list of functions that don't need escaping
The function `antispambot` takes an email address, and obfuscates it by encoding it using HTML entities. [Documentation](https://codex.wordpress.org/Function_Reference/antispambot)

For example, this code:

```php
echo antispambot( 'john.doe@mysite.com' );
```

This will output the email like this in the HTML:

```
&#106;&#111;h&#110;&#46;&#100;&#111;&#101;&#64;mysit&#101;.&#99;&#111;&#109;
```

PHPCS complains about that code, saying it should require escaping, when it doesn't.
