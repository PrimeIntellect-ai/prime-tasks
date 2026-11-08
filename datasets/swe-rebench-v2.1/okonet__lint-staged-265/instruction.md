Possible false positive in the config validation
Following config

```json
  "lint-staged": {
    "linters": {
      "*.js": [
        "npm run lint:js -- --fix",
        "git add"
      ],
      "*.json": [
        "npm run lint:js -- --fix",
        "git add"
      ],
      "*.md": [
        "npm run lint:md -- -o",
        "git add"
      ]
    },
    "verbose": true,
    "concurrent": false
  },
```

causes the following error when running lint-staged:

```
Running lint-staged with the following config:
{
	linters: {
		'*.js': [
			'npm run lint:js -- --fix',
			'git add'
		],
		'*.json': [
			'npm run lint:js -- --fix',
			'git add'
		],
		'*.md': [
			'npm run lint:md -- -o',
			'git add'
		]
	},
	verbose: true,
	concurrent: false,
	chunkSize: 9007199254740991,
	gitDir: '.',
	globOptions: {
		matchBase: true,
		dot: true
	},
	subTaskConcurrency: 1,
	renderer: 'verbose'
}

Could not parse lint-staged config.
Make sure you have created it. See https://github.com/okonet/lint-staged#readme.

Error: Invalid config provided to runAll! Use getConfig instead.


husky > pre-commit hook failed (add --no-verify to bypass)
```

Then config is changed to following error disappears:

```json
  "lint-staged": {
    "linters": {
      "*.js": [
        "npm run lint:js -- --fix",
        "git add"
      ],
      "*.json": [
        "npm run lint:js -- --fix",
        "git add"
      ],
      "*.md": [
        "npm run lint:md -- -o",
        "git add"
      ]
    },
    "verbose": true
  },
```
