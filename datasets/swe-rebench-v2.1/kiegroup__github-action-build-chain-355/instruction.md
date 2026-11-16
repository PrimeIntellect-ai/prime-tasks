fix job summary
In this [summary](https://github.com/kiegroup/droolsjbpm-build-bootstrap/actions/runs/3931901214/attempts/3#summary-10698719164) for the local execution part we are getting `undefined` and the order of arguments is wrong

```
npm i undefined@undefined -g build-chain-action -f https://raw.githubusercontent.com/${GROUP:kiegroup}/droolsjbpm-build-bootstrap/${BRANCH:main}/.ci/pull-request-config.yaml build cross_pr -u https://github.com/kiegroup/droolsjbpm-build-bootstrap/pull/2192
```

### Additional contract requirements

- For the `cross_pr` local-execution summary, render the command exactly as:
```
npm i @kie/build-chain-action -g
build-chain build cross_pr -f definitionFile -u eventUrl
```
