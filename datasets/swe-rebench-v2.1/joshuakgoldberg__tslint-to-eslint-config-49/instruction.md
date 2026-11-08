Include `sourceType: "module"` in parser options
See https://github.com/eslint/eslint/issues/4344. For now, let's include `sourceType: "module"` in outputs, as existing TypeScript projects that already have TSLint are very likely to use module mode for source types as it is.
