PurgeCSS remove first components class when using whitelist comment
Hi tailwindlabs team,

I noticed the following point with the building PurgeCSS.

If I import a CSS file before `@tailwind components;` and use PurgeCSS whitelist comment: `.container` classes are remove but not responsive container classes.

My Sass file
```
@tailwind base;

/* purgecss start ignore */
@import "button";
/* purgecss end ignore */

@tailwind components;

@tailwind utilities;
```

I make different test using exclamation mark in comment, ... same result

I use last tailwindcss 1.7.5, sass, csso.

My `tailwind.config.js`
```
module.exports = {
  purge: [
    'path/to/templates',
  ],
  future: {
    removeDeprecatedGapUtilities: true,
  },
  experimental: {
    applyComplexClasses: true,
    uniformColorPalette: true,
    extendedSpacingScale: true,
    defaultLineHeights: true,
    extendedFontSizeScale: true,
  },
}
```
