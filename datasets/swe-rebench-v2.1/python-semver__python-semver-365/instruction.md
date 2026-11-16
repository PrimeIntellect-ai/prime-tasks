Unable to create pre-release with an empty token
<!-- Remove the comments below and adapt it to your needs  -->

# Situation

Unable to create pre-release with an empty token.

# To Reproduce

Run this script:
```python
ver = semver.VersionInfo.parse('1.0.0')
ver = ver.bump_prerelease('');
print(ver)
# 1.0.0-rc.1
```

# Expected Behavior

`.bump_prerelease('')` should generate an version like `1.0.0-1`.

# Environment
- OS: Linux ubuntu 5.11.0-40-generic
- Python version: Docker image python:3.8
- Version of semver library: semver==2.13.0

# Additional context

Pre-release documentation https://semver.org/#spec-item-9
