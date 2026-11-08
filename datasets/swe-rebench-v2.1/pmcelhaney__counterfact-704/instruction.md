Trailing slashes on an endpoint?
### Discussed in https://github.com/pmcelhaney/counterfact/discussions/702

<div type='discussions-op-text'>

<sup>Originally posted by **dethell-jh** January  5, 2024</sup>
Some of our codebase has endpoint references written with a trailing slash such as: `${myApiUrl}/someEndPoint/`. This throws off Counterfact because even though I have a file at `paths/someEndPoint.ts` that handles the need, Counterfact is expecting a subpath after the trailing slash. If I update the codebase to remove the trailing slash it works, but I'm trying to get my Counterfact setup to be a drop-in for the API that doesn't require the UX side to make changes just to accommodate Counterfact. Ideas?</div>
