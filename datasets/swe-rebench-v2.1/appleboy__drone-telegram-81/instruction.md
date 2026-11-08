Message as auxiliary file
Hi @appleboy

the plugin is awesome, I really like it!

The only thing that bothers me (a little) is that I cannot configure the message in a side file.

It would be incredible if one is able to do the following:

Let's say: in `.drone-telegram-message.md`

```markdown
{{#success build.status}}
... here goes md content
{{else}}
... here goes md content
{{/success}}
```

Pros:
- file is supported by IDE by simply following its extension / file type
- no need to encode special yaml characters such as `#`, `:` etc.
- more readable .drone.yml

And then the config would look as

```yml
    name: telegram
    depends_on: [dockerize]
    image: appleboy/drone-telegram
    when:
      status: [success, failure]
    settings:
      token:
        from_secret: telegram_token
      to:
        from_secret: telegram_to
      format: markdown
      messageFile: .drone-telegram-message.md
```

What do you think?

### Additional contract requirements

- The message file path is configured through the plugin setting `message_file` (written as `messageFile` in the example above), exposed to the plugin as the `PLUGIN_MESSAGE_FILE` environment variable and the `message.file` command-line flag. When this setting is non-empty, `Plugin.Exec` loads the message from the referenced file.
