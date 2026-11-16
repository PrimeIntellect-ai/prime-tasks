False-negative cuddled assignment line above
My code:
```
	// Network constants
	networkConstants := bc.Current.CurrentConstants()
	log.WithFields(log.Fields{
		"PreservedCycles":       networkConstants.PreservedCycles,
		"BlocksPerCycle":        networkConstants.BlocksPerCycle,
		"BlocksPerRollSnapshot": networkConstants.BlocksPerRollSnapshot,
		"BlocksPerCommitment":   networkConstants.BlocksPerCommitment,
	}).Debug("Loaded Network Constants")
```

Linter error:
```
tribbles.go:61:2:only cuddled expressions if assigning variable or using from line above (wsl)
	log.WithFields(log.Fields{
```

As you can see, I am absolutely using the assigned variable from the line above. Not sure how to ignore this.
