Does $_FILES really need wp_unslash?
## Bug Description
I'm using `wp_handle_upload` in one of my plugins. PHPCS complains about the `$_FILES` slice not being run through `wp_unslash`. However, [`wp_magic_quotes` does not add slashes to `$_FILES`](https://developer.wordpress.org/reference/functions/wp_magic_quotes/).

Running an apparently superfluous `wp_unslash` on `$_FILES` is harmless on POSIX platforms, but [breaks file uploading on Windows](https://wordpress.org/support/topic/there-was-an-error-uploading-the-avatar-specified-file-failed-upload-test/).

## Minimal Code Snippet
```php
$mimetypes = [
	'jpg|jpeg|jpe' => 'image/jpeg',
	'gif'          => 'image/gif',
	'png'          => 'image/png',
];
$args = [
	'mimes'                    => $mimetypes,
	'test_form'                => false,
];
$avatar = \wp_handle_upload( \wp_unslash( $_FILES[ 'avatar' ], $args ) );
```

## Error Code
`WordPress.Security.ValidatedSanitizedInput.MissingUnslash`

## Environment

| Question               | Answer
| ------------------------| -------
| PHP version             | 7.3.6
| PHP_CodeSniffer version | 3.4.2
| WPCS version            | 2.1.1
| WPCS install type       | Composer project local

## Tested Against `develop` branch?
- [ ] I have verified the issue still exists in the `develop` branch of WPCS.
