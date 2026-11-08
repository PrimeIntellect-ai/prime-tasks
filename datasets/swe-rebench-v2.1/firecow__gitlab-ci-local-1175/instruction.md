Manually triggered jobs must not run if they're not specifically called via CLI
**Minimal .gitlab-ci.yml illustrating the issue**
```yml
---
stages:
  - plan
  - apply

plan:
  stage: plan
  environment:
    name: $CI_COMMIT_BRANCH
  script:
    - echo "i'm planning"
   rules:
    - if: '$CI_COMMIT_BRANCH =~ /dev/'
      changes:
        - folder
    - if: '$CI_COMMIT_BRANCH =~ /main/'
      changes:
        - folder
    - if: '$CI_PIPELINE_SOURCE == "web"'

apply :
  stage: apply
  environment:
    name: $CI_COMMIT_BRANCH
  script:
    - echo "i'm applying"
    #- terraform apply -input=false PLAN
  when: manual
  dependencies:
    - plan
  rules:
    - if: '$CI_COMMIT_BRANCH =~ /dev/'
      changes:
        - folder
    - if: '$CI_COMMIT_BRANCH =~ /main/'
      changes:
        - folder
    - if: '$CI_PIPELINE_SOURCE == "web"'
```

**Expected behavior**
Apply job must not run without recieving a manual confirmation of the user, i had it applied and build some unwanted infrastructure

**Host information**
Ubuntu 20.04
gitlab-ci-local 4.46.0

**Containerd binary**
I'm using docker

**Additional context**
This issue is related to [this other issue](https://github.com/firecow/gitlab-ci-local/issues/680), that had the exact same problem. I hope that i provided a most detailed example, but please let me know if you need more help with that. The tool is awesome BTW!
