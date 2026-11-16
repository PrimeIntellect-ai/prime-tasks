width and height don't do the right thing when they differ from width and height of sources
moved from [here](https://github.com/imgix/react-imgix/issues/45#issuecomment-288206488)
> Edit: issue seems to be coming from the generated fallback <img> element with the Picture Support. You need to define the width/height of the image on the parent <Imgix/> element otherwise it will load the 1x1 version by default on the fallback <img>! (crashing Safari/mobiles if you have big images by default).

something else i noticed yesterday in my work's codebase - you not only have to have a width/height on the parent element but it also needs to be the maximum width/height of any of the `<source>` elements that may be inside of the generated `<picture>`. so this:
```
<Imgix type="picture" src={src} width={100} height={100}>
  <Imgix type="source" src={src} width={400} height={100} imgProps={{ media: '(min-width: 768px)' }} />
</Imgix>
```

will load the 400x100 image on a large screen but will only display it as 100x100 (at least in chrome and safari)

i _think_ this is a bug - in my local testing setting the provided height/width on the fallback image but changing the same attributes on the parent container to the maximum values did the right thing everywhere. working around it doesn't seem hard but it's unclear if that's the expected behavior though. should i just open a new bug to discuss this?

### Additional contract requirements

- When a picture-mode component has no fallback image among its children, it must call `console.warn` with a message containing the exact text `No fallback image found`; the call must have exactly one argument.

- In picture mode, callers are responsible for giving the picture and its fallback image width and height that are at least the greatest corresponding dimensions requested by any source child. The component does not infer or enlarge these dimensions from source children. This prevents a selected larger source from being constrained to smaller fallback sizing.
