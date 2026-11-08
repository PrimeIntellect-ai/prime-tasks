Fix arbitrary value using `color-mix()` function not being recognized as color
Problem from https://x.com/initjean/status/1932440932277752225 and https://gist.github.com/JeanMeijer/2471088dcabb136ca6f906054f4df723.

`border-[color-mix(in_oklab,var(--background),var(--calendar-color)_30%)]` and `border` are merged together because of the `30%` in the arbitrary value being recognized as a length. But `color-mix()` should give us signal that this is a color instead.
