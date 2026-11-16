Updated month prop not updating the calendar when displaying multiple months
`6.x` it work very well, but when i update to `7.x`, the `month` cannot causes the calendar to re-render when its value changes.

i save the `month` in component's state, and it looks like: http://react-day-picker.js.org/examples/elements-year-navigation

but i set the `numberOfMonths` to `2`. and then setState from `captionElement`.
the logs:

![image](https://user-images.githubusercontent.com/929878/33541347-32c831a4-d912-11e7-9230-aa2d78689bf0.png)

in `handleChange` i got the right date, `201706`, then setState to component,
then the `captionElement` got the `201711` and `201712`.

then i try to change not use state cause picker rerender, change to `showMonth`.
now it work.

ok, then i read the docs, and try to use `onMonthChange` to keep the `currentMonth` to the state, but WTF, you see that? `captionElement` use the old values.

there is no BREAKINGCHANGE in the CHANGELOG and there is no docs in anywhere.
so , i cannot use 7.x. @gpbl could you help me ?

my code:

![image](https://user-images.githubusercontent.com/929878/33541824-f385f042-d913-11e7-8349-0bb01cba00c1.png)

### Additional contract requirements

When the controlled `month` prop changes, the displayed calendar must reflect the requested month, including when multiple months are shown; the rendered month captions must not remain stale.
