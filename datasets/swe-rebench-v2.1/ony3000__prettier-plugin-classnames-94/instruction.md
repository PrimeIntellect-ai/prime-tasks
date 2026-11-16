Svelte: expressions within class list breaks the formatter or causes unexpected behavior
Hi there! Thanks for the plugin, very useful :)

I did just come across unexpected behavior when using JS expressions in class names in Svelte files.

In Svelte, pretty much any expression is allowed there when surrounded with curly brace.
A [very common pattern for conditional classes is the use of a ternary expression](https://svelte.dev/tutorial/svelte/classes), but that appears to break the formatter in several ways.

## Dependency information
```json
"prettier": "^3.5.3",
"prettier-plugin-classnames": "^0.7.7",
"prettier-plugin-merge": "^0.7.3",
"prettier-plugin-svelte": "^3.3.3",
```

## Prettier configuration
```json
{
	"useTabs": true,
	"singleQuote": true,
	"trailingComma": "all",
	"printWidth": 100,
	"plugins": ["prettier-plugin-svelte", "prettier-plugin-classnames", "prettier-plugin-merge"],
	"overrides": [
		{
			"files": "*.svelte",
			"options": {
				"parser": "svelte"
			}
		}
	]
}
```

## Steps to reproduce
Sample file:
```svelte
<!-- test.svelte -->

<script>
  let anyBoolean = false;
</script>

<div class="very long class name for reference to easily see if formatting still happens or not wow such a long name when will it ever end"></div>

<!-- these lines will format but the space before the curly braces wrapping the expression will be removed -->
<!-- (this is a problem) -->
<div class="clazz clazz clazz {anyBoolean ? 'yes' : 'no'}"></div>
<div class="clazz clazz clazz {'any JS or TS expression'}"></div>


<!-- adding any class after an expression causes formatting to fail entirely for the file -->
<!-- uncomment any of the two following lines to try it out -->

<!-- <div class="clazz clazz clazz {anyBoolean ? 'yes' : 'no'} broken"></div> -->
<!-- <div class="clazz clazz clazz {'any JS or TS expression'} broken"></div> -->
```

## The current behavior
Explained (or see for yourself) in the sample file provided.
Stack trace when formatting fails in the last section :
```
["INFO" - 10:49:13 PM] Prettier Options:
{
  "filepath": “(redacted)/Test2.svelte",
  "parser": "svelte",
  "useTabs": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "plugins": [
    "(redacted)/node_modules/prettier-plugin-svelte/plugin.js",
    "(redacted)/node_modules/prettier-plugin-classnames/dist/index.js",
    "(redacted)/node_modules/prettier-plugin-merge/dist/index.js"
  ]
}
["ERROR" - 10:49:13 PM] Error formatting document.
["ERROR" - 10:49:13 PM] The second format failed. This is likely a bug in this plugin. Please file an issue.
    Error: Expected token }
    https://svelte.dev/e/expected_token
      15 | <!-- adding any class after an expression causes formatting to fail entirely for the file -->
      16 | <!-- uncomment any of the two following lines to try it out -->
    > 17 |
         | ^
      18 | <!-- <div class="clazz clazz clazz {anyBoolean ? 'yes' : 'no'} broken"></div> -->
      19 | <div class="clazz clazz clazz{'any JS or TS expression' broken></div>
      20 |
Error: The second format failed. This is likely a bug in this plugin. Please file an issue.
    Error: Expected token }
    https://svelte.dev/e/expected_token
      15 | <!-- adding any class after an expression causes formatting to fail entirely for the file -->
      16 | <!-- uncomment any of the two following lines to try it out -->
    > 17 |
         | ^
      18 | <!-- <div class="clazz clazz clazz {anyBoolean ? 'yes' : 'no'} broken"></div> -->
      19 | <div class="clazz clazz clazz{'any JS or TS expression' broken></div>
      20 |
    at Object.parse ((redacted)/node_modules/prettier-plugin-classnames/dist/index.js:3:3623)
    at async parse5 (file://(redacted)/node_modules/prettier/index.mjs:19983:11)
    at async coreFormat (file://(redacted)/node_modules/prettier/index.mjs:20531:25)
    at async formatWithCursor (file://(redacted)/node_modules/prettier/index.mjs:20743:14)
    at async Module.format2 (file://(redacted)/node_modules/prettier/index.mjs:22182:25)
    at async (redacted)/node_modules/prettier-plugin-merge/dist/index.js:2:1166
    at async Se ((redacted)/node_modules/prettier-plugin-merge/dist/index.js:2:1048)
    at async Object.parse ((redacted)/node_modules/prettier-plugin-merge/dist/index.js:2:2001)
    at async parse5 (file://(redacted)/node_modules/prettier/index.mjs:19983:11)
    at async coreFormat (file://(redacted)/node_modules/prettier/index.mjs:20531:25)
["INFO" - 10:49:13 PM] Formatting completed in 27ms.
```

## The expected behavior
Treat expressions or anything wrapped in curly braces as a single word. Break the line before or after, but don't change anything within them and don't remove spaces.

Thanks in advance for taking a look ;)
