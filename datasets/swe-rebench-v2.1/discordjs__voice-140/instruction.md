I use the connection.disconnect() feature but it stays in VC.
**My bot is in VC. I try to disconnect it when there is no song playing. It doesn't leave or give an error.**

```js
const { getVoiceConnection } = require('@discordjs/voice');
const { MessageEmbed } = require('discord.js');

module.exports.run = async (bot, message, args, queue) => {
    if (!message.member.voice.channel) return message.channel.send({ content: `What? Excuse me? Do you really expect me to execute a MUSIC command without you being in a voice channel? Like how you gonna use them if you can't hear them bruh? Big brain much?` });

    if (queue === undefined) {
        const connection = getVoiceConnection(message.guild.id)
        connection.disconnect()
        message.channel.send({
            embeds: [new MessageEmbed()
                .setDescription("Thanks for tuning in!")
                .setColor("RED")
            ]
        })
        message.react("✅")
    } else {
        bot.distube.stop(message)
        message.react("✅")
        queue.voice.leave()
        message.channel.send({
            embeds: [new MessageEmbed()
                .setDescription("Thanks for tuning in!")
                .setColor("RED")
            ]
        })
    }
};
module.exports.config = {
    name: "disconnect",
    aliases: ["dc"]
}
```

**Further details:**

- @discordjs/voice version: 0.5.0
- Node.js version:14.17.1
- Operating system: Windows 10
- Priority this issue should have – please be realistic and elaborate if possible: not really at the top but is inconvinient.

**Relevant client options:**

- partials: none
- gateway intents: all
- other: none
