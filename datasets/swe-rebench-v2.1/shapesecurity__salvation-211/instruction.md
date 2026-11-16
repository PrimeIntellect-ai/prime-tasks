Incorrect behavior when merging policies that don't contain fetch directives
Merging empty policy with `script-src a` should produce empty policy ` `.

Similarly, merging `frame-ancestors a` with `script-src a` should produce `frame-ancestors a`,
as policy that does not contain fetch directives yields `script-src` to be not governed by CSP at all, rather than yielding `script-src *`.
