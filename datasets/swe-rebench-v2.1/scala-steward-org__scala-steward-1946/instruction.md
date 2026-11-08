Steward updates different artifacts with same version number
See https://github.com/playframework/play-ws/pull/461/files#diff-0:

![Screenshot 2020-02-11 at 12 05 46](https://user-images.githubusercontent.com/762126/74231435-db9daa00-4cc6-11ea-886b-4392a56f7412.png)

The steward was updating `scalafmt` from `2.0.1` to `2.0.7` and (incidentally) `sbt-pgp` got updated from `2.0.1` to `2.0.7` (which doesn't exist) too.
