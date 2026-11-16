<Link> component does not respect target attribute
Hi there, thanks for the great library!

I am not sure if it's a bug or if working as designed, I'll let you decide that, but the documentation states:

> The preferred method for navigation is the `<Link>` component, which uses all the same properties as the standard `<a>` element, and requires href.

...while in practice, when setting a `target` prop on the `<Link>` component it does not behave as expected (not as an `<a>` tag would).

E.g.: `<Link href="/dashboard" target="_blank" />` for which you would expect the link to open in a new tab.

You could argue that there is no reason to use a `<Link>` component for this use case and just revert to using a simple `<a>` instead, which would be fair.
