Cannot nest `<style>..</style>` inside script tag
Hey all,

Here's a bizarre random behavior with an incredibly small reproduction.

When creating this file:
```typescript
<script lang="ts">
  const test = '<style>.cls-1{fill:#231f20;}.cls-2{fill:#b06010;}.cls-3{fill:#578bac;}.cls-4{fill:#00446a;}.cls-5{fill:#afb1b4;}.cls-6{fill:#696a6d;}.cls-7{fill:#d7a374;}.cls-8{fill:#c1c17d;}.cls-9{fill:#8a8d09;}</style>'
</script>
```

If I format it:
```typescript
<script lang="ts">
	const test =
		'<style ✂prettier:content✂="LmNscy0xe2ZpbGw6IzIzMWYyMDt9LmNscy0ye2ZpbGw6I2IwNjAxMDt9LmNscy0ze2ZpbGw6IzU3OGJhYzt9LmNscy00e2ZpbGw6IzAwNDQ2YTt9LmNscy01e2ZpbGw6I2FmYjFiNDt9LmNscy02e2ZpbGw6IzY5NmE2ZDt9LmNscy03e2ZpbGw6I2Q3YTM3NDt9LmNscy04e2ZpbGw6I2MxYzE3ZDt9LmNscy05e2ZpbGw6IzhhOGQwOTt9"></style>';
</script>
```

That's... weird.

Here's my .prettierrc:
```json
{
	"useTabs": true,
	"singleQuote": true,
	"trailingComma": "es5",
	"printWidth": 120
}

```
