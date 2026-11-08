prefix/suffix not working?
### Behaviour

I am unable to add a prefix or suffix in v2 of this action, regardless if specified in the flavor or in the tag attributes.

#### Steps to reproduce this issue

1. Specify `suffix=-dev` in flavor or individual tag
2. Run action
3. Suffix is not applied

#### Expected behaviour

The action should append the suffix to the tag

#### Actual behaviour

The suffix is not appended

### Configuration

* Repository URL (if public): https://github.com/strophy/js-drive
* Build URL (if public): https://github.com/strophy/js-drive/runs/2288637313

```yml
- name: Set -dev suffix
  id: release_type
  run: |
    if [[ ${{ contains(github.event.release.tag_name, '-dev') }} = true ]]
    then
      echo '::set-output name=dev-suffix::-dev'
    else
      echo '::set-output name=dev-suffix::'
    fi

- name: Docker meta
  id: docker_meta
  uses: crazy-max/ghaction-docker-meta@v2
  with:
    images: strophy/drive
    tags: |
      type=match,pattern=v(\d+),group=1
      type=match,pattern=v(\d+.\d+),group=1
      type=match,pattern=v(\d+.\d+.\d+),group=1
      type=match,pattern=v(.*),group=1,suffix=,enable=${{ contains(github.event.release.tag_name, '-dev') }}
    flavor: |
      latest=${{ !contains(github.event.release.tag_name, '-dev') }}
      suffix=${{ steps.release_type.outputs.dev-suffix }}
```

### Logs
[logs_396.zip](https://github.com/crazy-max/ghaction-docker-meta/files/6272603/logs_396.zip)

### Additional contract requirements

- A configured prefix is prepended to generated tags, whether it is set in the flavor or on an individual tag.
- A `prefix` or `suffix` set on an individual tag takes precedence over the `prefix` or `suffix` set in the flavor. This includes an explicitly empty value (for example `suffix=`), which means the flavor value is not applied to that tag.
