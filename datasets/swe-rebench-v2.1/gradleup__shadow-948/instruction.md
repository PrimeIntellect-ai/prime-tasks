Gigantic jar when using Gradle 8.x
Please check the [User Guide](http://imperceptiblethoughts.com/shadow) before submitting "how do I do 'x'?" questions!

### Shadow Version

8.1.1

### Gradle Version

8.6

### Expected Behavior

Should only need to shadow bouncycastle dependencies, and resulting jar should be small, with just bouncycastle relocated.

### Actual Behavior

Without adding a number of other dependencies, the resulting jar was not usable by our code, which failed at runtime with missing-class exceptions.

See comment in shadow-bad's dependency.gradle that starts with "// If this dependencies{} block is commented out".

[shadow-good.zip](https://github.com/johnrengelman/shadow/files/14529660/shadow-good.zip)

[shadow-bad.zip](https://github.com/johnrengelman/shadow/files/14529663/shadow-bad.zip)
