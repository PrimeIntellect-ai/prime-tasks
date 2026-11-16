sonarcloud scan not performing PR analysis
Since we merge source into target and then run sonar cloud analysis on that, that sonar cloud analyzes the code in context of the target branch rather than source. Hence it is not able to show any PR analysis.

build-chain v2 renamed the branch to fix this issue. For now we will replicate that since it was stable.

For future once v3 stabilizes we should prepare for a generic solution that mimics github behavior just so that it is compatible with anything new. Tracked by #394

### Additional contract requirements

After a successful merge of a source branch into a target checkout, the checkout's current branch must identify as the source branch. This allows subsequent SonarCloud analysis to run in the source context and report pull-request analysis.
