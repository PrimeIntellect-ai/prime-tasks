[Bug]: @php blocks handled differently when nested in @if blocks
### Description

Please reference https://github.com/shufo/blade-formatter/pull/909#issuecomment-1962253902

Here I show a screenshot where the `@php` block is severely wrapped but another block below is unaffected. I had only noticed the changed after upgrading from 1.32 and believe it is a difference due to the bugfix in 1.34.1.



### Expected Behavior

But I am confused now...I thought the line length might already ignore the indentation level. Apparently not. I guess it was not getting wrapped, though I don't know why the constant of printWidth wasn't working when I had 120 set for wrap length anyway.

### Actual Behavior

Is the length of the wrap always including the indentation space? Is there a way to exempt indentation?

Is the difference in `@php` block formatting expected when nested in an `@if` block? The above section wraps after an `=` but the lower section does not.

### Additional Context

v1.41.0
[Formatting Bug]: issues formatting indented @php blocks following #909 and v1.41.0
### Version

1.41.0

### Template before formatting

```blade
@php
    if (1) {
        if (1) {
            if (1) {
                if (1) {
                    if (1) {
                        if (1) {
                            $percent =
                                $item['historical'] ?? null
                                    ? round(
                                        (100 *
                                            ($item['today'] -
                                                $item['historical'])) /
                                            $item['historical'],
                                    )
                                    : null;

                            $color = $percent < 0 ? '#8b0000' : '#006400';
                        }
                    }
                }
            }
        }
    }
@endphp

<div>
    <div>
        <div>
            <div>
                <div>
                    <div>
                        @php
                            $percent =
                                $item['historical'] ?? null
                                    ? round(
                                        (100 *
                                            ($item['today'] -
                                                $item['historical'])) /
                                            $item['historical'],
                                    )
                                    : null;

                            $color = $percent < 0 ? '#8b0000' : '#006400';
                        @endphp
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
```


### Template after formatting

```blade
@php
    if (1) {
        if (1) {
            if (1) {
                if (1) {
                    if (1) {
                        if (1) {
                            $percent =
                                $item['historical'] ?? null
                                    ? round(
                                        (100 *
                                            ($item['today'] -
                                                $item['historical'])) /
                                            $item['historical'],
                                    )
                                    : null;

                            $color = $percent < 0 ? '#8b0000' : '#006400';
                        }
                    }
                }
            }
        }
    }
@endphp

<div>
    <div>
        <div>
            <div>
                <div>
                    <div>
                        @php
                            $percent =
                                $item[
                                    'historical'
                                ] ??
                                null
                                    ? round(
                                        (100 *
                                            ($item[
                                                'today'
                                            ] -
                                                $item[
                                                    'historical'
                                                ])) /
                                            $item[
                                                'historical'
                                            ],
                                    )
                                    : null;

                            $color =
                                $percent <
                                0
                                    ? '#8b0000'
                                    : '#006400';
                        @endphp
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
```


### Expected Behaviour

This code was reported by @calebdw at https://github.com/shufo/blade-formatter/pull/909#issuecomment-1961581690, and I've reproduced it here.

The PHP code in these blocks is indented to the same level and I would expect it to be formatted identically. In particular, the second statement (the ternary) fits into 79 chars, including indentation, and it should be left on a single line.

I can reproduce 1-token-per-line wrapping that @calebdw is seeing, but only after smashing that PHP into so many `if`s that every line exceeds the wrap limit (see below). This strongly suggests that we're telling prettier to format these to the wrong `printWidth`, because it's treating everyline line it's already exceeded the print width.

I can look into this, but it will be a few days.

**Reproduction snippet with extreme wrapping**
```
@php
    if (1) {
        if (1) {
            if (1) {
                if (1) {
                    if (1) {
                        if (1) {
                            if (1) {
                                if (1) {
                                    if (1) {
                                        if (1) {
                                            if (1) {
                                                if (1) {
                                                    if (1) {
                                                        if (1) {
                                                            if (1) {
                                                                if (1) {
                                                                    if (1) {
                                                                        $percent =
                                                                            $item[
                                                                                'historical'
                                                                            ] ??
                                                                            null
                                                                                ? round(
                                                                                    (100 *
                                                                                        ($item[
                                                                                            'today'
                                                                                        ] -
                                                                                            $item[
                                                                                                'historical'
                                                                                            ])) /
                                                                                        $item[
                                                                                            'historical'
                                                                                        ],
                                                                                )
                                                                                : null;

                                                                        $color =
                                                                            $percent <
                                                                            0
                                                                                ? '#8b0000'
                                                                                : '#006400';
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
@endphp
```


### Relevant log output

_No response_

### Additional contract requirements

- When the same PHP content appears at the same indentation relative to its `@php` block under different surrounding nesting, the formatted PHP content should be identical apart from the indentation contributed by the surrounding template.
- A ternary expression whose complete line, including indentation, fits within 79 characters should remain on one line.
