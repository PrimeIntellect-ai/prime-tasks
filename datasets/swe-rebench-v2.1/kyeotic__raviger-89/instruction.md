useLocationChange is called on mount
Hi @kyeotic!

We have just upgraded `raviger` from version `1.6.0` to version `2.0.2` and we are facing a problem with a new behaviour introduced in `2.0.0` in `useLocationChange`.

`useLocationChange` will now call its callback argument on mount due to this `useLayoutEffect`:
https://github.com/kyeotic/raviger/blob/74e3b87eaf108d0950ab09f368f1f91f23345dcb/src/path.js#L93-L98

Is that completely intended? Or should that be a layout effect that only gets executed after the initial mount?

Our use case for `useLocationChange` is within modals that we want to close when the user hits the Back/Forward browser history buttons:
```jsx
// close the modal when the path has changed
useLocationChange(onClose);
```

With `2.0.2`, this code gets executed when the modal is mounted and thus it closes instantly.
