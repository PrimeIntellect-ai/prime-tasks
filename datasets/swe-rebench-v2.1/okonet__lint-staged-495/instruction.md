File matching a parent directory
I just have a question of file matching and dont even know if this is possible. I have my package.json in a subfolder `/docroot/themes/custom/my_theme/package.json` and I am using lint-staged to run some precommit git hooks, but I cant get the file pattern matching to work for files that are in parent directories.

I want to search for files in `/docroot/modules/custom/**/*.php`

I have tried

```
"docroot/modules/custom/**/*.php": [
  "phpcs --standard=Drupal"
]

"/docroot/modules/custom/**/*.php": [
  "phpcs --standard=Drupal"
]

"modules/custom/**/*.php": [
  "phpcs --standard=Drupal"
]

"../../../modules/custom/**/*.php": [
  "phpcs --standard=Drupal"
]
```

and I cannot get any of them to match files. My git root is in the `/docroot` folder. Any ideas?

### Additional contract requirements

- A configured pattern beginning with `../` must be able to match and process staged files in a parent directory of the current working directory.
- Patterns that do not target parent directories must retain the existing behavior of matching only files inside the current working directory.
