`jsx-no-bind` errors on non-react components.
I have Backbone views with a "render" method that are being warned when they have `.bind` used within them. Did something change recently that loosened the criteria for identifying a React component?

If the `render` method doesn't return JSX, and the component doesn't `extend React.Component`, and most importantly if the file itself doesn't even import/require `React`, why are these rules applying to it?
