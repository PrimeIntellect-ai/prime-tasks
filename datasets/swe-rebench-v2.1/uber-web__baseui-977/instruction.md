Popovers violate invariant rendering after ssr
<!--- Provide a general summary of the issue in the Title above -->
I pulled in the latest alpha of [fusion-react](https://github.com/fusionjs/fusion-react/releases/tag/v2.0.0-alpha.2), and was testing out baseui components which are server side rendered, but the popover component was throwing invariant violations, `Invariant Violation: Portals are not currently supported by the server renderer. Render them conditionally so that they only appear on the client render.`:

![image](https://user-images.githubusercontent.com/877194/53689350-6e3c7780-3d08-11e9-8383-1e56ed7512c8.png)


## Current Behavior
Popovers initially ssr rendered with the following code will error

```
<Popover isOpen={true} content={...}>{...}</Popover>
```
<!---
    Describe what happens instead of the expected behavior.
-->

## Expected Behavior
Component renders without error
<!---
    Describe what should happen.
-->

## Current Workaround
```
function ExComp() {
  // hooks way of `componentDidMount`
  const [initialized, setInitialized] = useState(false);
  useEffect(() => {
    setInitialized(true);
  });

  return <Popover isOpen={initialized}content={...}>{...}</Popover>
}
```
which still throws warnings...
![image](https://user-images.githubusercontent.com/877194/53689452-37b42c00-3d0b-11e9-9916-0d08eb143e96.png)

## Your Environment

<!--- Include as many relevant details about the environment with which you experienced the bug. -->
```
❯ npm ls react-dom
└── react-dom@16.8.3
❯ npm ls baseui
└── baseui@5.14.0
```


To get the same env, run a [fusion.js](https://fusionjs.com/) app. Add baseui of course, and then either build yourself the latest alpha of [fusion-react](https://github.com/fusionjs/fusion-react/releases/tag/v2.0.0-alpha.2)  or just alias the following forked & scoped package which includes it...
```
yarn add fusion-apollo@npm:@enjoylife/fusion-apollo # to get the alpha dist of fusion-react i'm usin
```

- [x ] I have searched the [issues](https://github.com/uber-web/baseui/issues) of this repository and believe that this is not a duplicate.

### Additional contract requirements

- An initially open Popover must render without error during server-side rendering.
- When a Popover mounts, it must generate a unique popover id.
- After a Popover has mounted, its anchor element must expose the generated popover id through accessibility attributes: for the default menu accessibility type, `aria-haspopup` is `"true"`, `aria-expanded` reflects whether the popover is open, and `aria-controls` is the generated popover id while the popover is open (and `null` while it is closed). The popover body must carry the generated popover id.
