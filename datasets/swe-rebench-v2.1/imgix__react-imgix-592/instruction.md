<Background /> with a width (and `top`) but no height causes Imgix 400
Currently the `Background` component is set up in such a way where if the image "isn't ready", then it doesn't attempt a render.

This is great, except for the "is ready" check, [HIDDEN] However, a very common flow will be that the DOM _node_ is ready (i.e. it is in the DOM, and thus has a truthy `top`), but the CSS/layout hasn't finished rendering fully, such that the DOM still has no width/height.

This results in react-imgix trying to use a `height` of `0`, which then ends up giving `const ar = contentRect.bounds.width / contentRect.bounds.height;` an `ar` of `NaN`, and ends up with imgix URLs of e.g. `/blah/foo.jpeg?ar=3%3A4&fit=crop&h=NaN&q=80&w=100`

This then has react-imgix hit a 400

### Additional contract requirements

- When either `bounds.width` or `bounds.height` is null, the rendered `<div>` must not have a `background-image` style, and no background image URL may be rendered.
