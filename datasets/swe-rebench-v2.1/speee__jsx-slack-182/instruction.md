Add React-compatible camelCase prop <time dateTime>
jsx-slack has supported HTML style `<time datetime>` attribute. On the other hand, React uses camelCase prop `<time dateTime>` normally. Both will work in React but not in jsx-slack.

For compatibility of React JSX, it's good to add an alias prop `dateTime` for `datetime` attribute.
