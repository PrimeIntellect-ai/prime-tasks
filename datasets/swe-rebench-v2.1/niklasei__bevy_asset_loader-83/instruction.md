For empty LoaderState it should immidiatly transfer the state
I discovered this bug by commenting and uncommenting code to debug an issue. If `LoaderState` is empty, the transition to new state will never happen instead of happening immidiatly.
