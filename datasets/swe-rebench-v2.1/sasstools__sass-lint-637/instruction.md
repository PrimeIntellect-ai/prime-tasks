no-misspelled-properties is incorrectly failing on '-moz-osx-font-smoothing'
I got around this issue by providing this exception to my config, but this would seem to be an error to me since font-awesome and many other icon fonts define this property for firefox.
```
  no-misspelled-properties:
    - 2
    - 'extra-properties':
          - 'osx-font-smoothing'
```
