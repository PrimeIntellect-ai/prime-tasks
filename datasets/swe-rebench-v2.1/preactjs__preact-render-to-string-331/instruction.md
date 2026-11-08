Rendering shallow makes a Fragment into a <p>
Shallow rendering this:
`<><ComponentX /></>`
Creates this:
`<p><ComponentX /></p>`

Is that intended behaviour? Why not just `<ComponentX />`

### Additional contract requirements

- In shallow rendering, Fragments should be transparent, including when returned by a functional component: render their children without a Fragment wrapper.
