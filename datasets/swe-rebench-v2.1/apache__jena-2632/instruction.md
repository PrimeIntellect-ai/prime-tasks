DocumentGraphRepository: prevent double loading of the same graph
### Version

5.1.0

### Feature

Currently, it is possible to load the same document source multiple times, which will result in several different graphs with the same data.
I think it would be more convenient and useful to change `DocumentRepository#addMapping` so that it doesn't create a new source every time.

Related discussion: https://lists.apache.org/thread/tb58m9c84rvov2zgotdo43r1g7xc61r1

### Are you interested in contributing a solution yourself?

Yes
