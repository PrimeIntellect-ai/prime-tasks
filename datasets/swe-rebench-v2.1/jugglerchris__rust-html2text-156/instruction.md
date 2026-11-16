Imbricated tables in HTML emails and --css --ignore-css-colour
I updated my patched version of the html2text script with the new 0.13 release, I tested it on a few emails and **found one email that did not output anything.**

I'm using `--colour --css --ignore-css-colour` to get custom text formats but still hide some elements that should not appear.

There is no zero height element or any reference to display or overflow in the email sources, but ater some tests **I found that if I remove the top 'tr' and 'td' opening and closing tags in the parent table, it works then, every other element is inside imbricated tables inside this one.**

The concerned html email:

- I patched html2text.rs with `config = config.raw_mode(true);` and some changes in `match annotation {}`, then I build with `cargo build --features css --example html2text`
- I run with `html2text --width 80 --wrap-width 80 --colour --ignore-css-colour --css email.html`
- Removing lines 9, 10, 82 and 83 in the email fixes the issue.

``` html
<html>
<head>
<meta content="width=device-width" name="onboarding-uptimerobot"/>
<meta content="text/html; charset=utf-8" http-equiv="content-type"/>
<title>📲 SMS/Voice calls: Stay updated anytime, anywhere!</title>
</head>
<body style="font-family: 'Roboto', Arial, sans-serif; color: #131a26; background: #fefefe;">
<table border="0" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0px auto 0 auto; padding: 0 10px;">
<tr style="font-family: 'Roboto', Arial, sans-serif; color: #131a26; background: #fefefe;">
<td style="font-family: 'Roboto', Arial, sans-serif; color: #131a26; background: #fefefe;">
<table border="0" cellpadding="0" cellspacing="0" style="max-width: 600px; margin: 0px auto 0 auto; padding: 0 10px;">
<tr style="max-width: 600px; margin: 0px auto 0 auto; padding: 0 10px;">
<td style="max-width: 600px; margin: 0px auto 0 auto; padding: 0 10px;">
<table border="0" cellpadding="0" cellspacing="0">
<tr>
<td style="color: #ffffff; background:#131a26; border-radius: 6px 6px 0 0; box-shadow: 0 20px 40px 0 rgba(0,0,0,0.1); padding: 6px 0 0 0; font-size: 14px;">
<a href="https://uptimerobot.user.com/emails/c/eM9oWZX0/?to=https%3A%2F%2Fapp.uptimerobot.com%2Fbilling%2Fcheckout%2Fextra-credits%2F%3Futm_source%3Duser_com%26utm_medium%3Demail%26utm_campaign%3Dsms-calls-promo-free">
<img alt="" src="https://uptimerobot.user.com/uploads/su5k6k-uptimerobot/email-enable-sms-promo_DfAjPuj.png" style="width: 100%;"/>
</a>
</td>
</tr>
</table>
<table border="0" cellpadding="0" cellspacing="0">
<tr>
<td style="color: #ffffff; background:#131a26; border-radius: 0 0 6px 6px; box-shadow: 0 20px 20px 0 rgba(0,0,0,0.1); padding: 1px 35px; font-size: 14px;">
<p style="line-height: 22px; margin-bottom: 30px; padding-left: 30px; padding-right: 30px;">
                        Hey there!
                      </p>
<p style="line-height: 22px; margin-bottom: 30px; padding-left: 30px; padding-right: 30px;">
                        Did you know we can notify you about incidents via SMS or voice calls? 📲
                      </p>
<h3 style="line-height: 22px; padding-left: 30px; padding-right: 20px; color: #3bd771">
                        Why use SMS/Voice call alerts?
                      </h3>
<ul style="line-height: 22px; margin-bottom: 30px; padding-left: 50px; padding-right: 30px;">
<li>SMS/Voice calls work without an internet connection.</li>
<li>They won't get lost in tons of emails or push notifications.</li>
<li>Try it out with our special entry package: <b style="color: #3bd771">Get 10 SMS/voice call credits for only $3!</b>
</li>
</ul>
<p style="line-height: 22px; margin-bottom: 40px; margin-top: 30px">
<a href="https://uptimerobot.user.com/emails/c/eM9QO1ZX0/?to=https%3A%2F%2Fapp.uptimerobot.com%2Fbilling%2Fcheckout%2Fextra-credits%2F%3Futm_source%3Duser_com%26utm_medium%3Demail%26utm_campaign%3Dsms-calls-promo-free" style="width: 220px; max-width: 90%; line-height: 48px; background-color:#3bd771; color: #fff; display: block; margin: 0 auto; text-decoration: none; border-radius: 28px; font-size: 16px; text-align: center; font-weight: bold; vertical-align: middle;">Buy SMS/Call credits</a></p>
<p style="line-height: 22px; margin-bottom: 30px; padding-left: 30px; padding-right: 30px;">Have a great (up)time!<br/>
                        Lucia from UptimeRobot</p>
</td>
</tr>
</table>
</td>
</tr>
</table>
<table style="width: 100%">
<tr>
<td style="font-size: 12px; color: #687790; text-align: center; padding: 15px 0; font-family: 'Roboto',sans-serif;">
<p style="font-size: 16px; text-align: center; color: #131a26;"><b>Join our <a href="https://uptimerobot.user.com/emails/c/9kvRxzDWeM0/?to=https%3A%2F%2Fdiscord.com%2Finvite%2FJRBar2vA5N" style="font-size: 16px; text-align: center; color:#3bd771;">Discord</a>. Stay updated<span style="color:#3bd771;">.</span> Earn rewards<span style="color:#3bd771;">.</span></b></p>
<p style="box-sizing: border-box; font-size: 12px; line-height: 130%;">
<a href="https://uptimerobot.user.com/emails/c/axoKy6PXQ92d/?to=https%3A%2F%2Fwww.facebook.com%2FUptimeRobot%2F">
<img alt="uptimerobot-facebook" height="auto" src="http://cdn.mcauto-images-production.sendgrid.net/3e8054f26aace367/ab7d7dc4-d774-407a-a021-359470531d13/64x64.png" width="32"/></a>
<a href="https://uptimerobot.user.com/emails/c/05mR0X861Rk1A/?to=https%3A%2F%2Ftwitter.com%2Fuptimerobot">
<img alt="uptimerobot-twitter" height="auto" src="http://cdn.mcauto-images-production.sendgrid.net/b0f7060ce6d5fe3b/2852c673-3641-4439-a082-7b8a02f11784/64x64.png" width="32"/></a>
<a href="https://uptimerobot.user.com/emails/c/5woQzn5QJpn/?to=https%3A%2F%2Fwww.linkedin.com%2Fcompany%2Fuptime-robot%2F">
<img alt="uptimerobot-linkedin" height="auto" src="http://cdn.mcauto-images-production.sendgrid.net/3e8054f26aace367/bec4a5fa-247f-480f-8e75-d9edc9fdcb29/64x64.png" width="32"/></a>
<a href="https://uptimerobot.user.com/emails/c/A98WXkKv2l/?to=https%3A%2F%2Fdiscord.gg%2FJRBar2vA5N">
<img alt="uptimerobot-discord" height="auto" src="http://cdn.mcauto-images-production.sendgrid.net/b0f7060ce6d5fe3b/30a85fbe-fbe8-4148-92f8-63b7cfc8bdb3/64x64.png" width="32"/></a>
</p>
<p style="font-size: 12px; text-align: center; color: #999;">
<a href="https://uptimerobot.user.com/emails/c/OVPR3/?to=https%3A%2F%2Fuptimerobot.com%2Fpricing%2F" style="font-size: 12px; text-align: center; color: #999;">Pricing</a> | <a href="https://uptimerobot.user.com/emails/c/oPDK44J0vKg0j/?to=https%3A%2F%2Fblog.uptimerobot.com%2F" style="font-size: 12px; text-align: center; color: #999;">Blog</a> | <a href="https://uptimerobot.user.com/emails/c/axo2MrQ92d/?to=https%3A%2F%2Fuptimerobot.com%2Faffiliate%2F" style="font-size: 12px; text-align: center; color: #999;">Affiliate</a></p>
<br/>
<p>
<span style="color: #999; font-size: 10px;">
                    Uptime Robot Service Provider Ltd.<br/>
                    Regent House, Office 21, Bisazza Street,
                    Sliema SLM1640,
                    Malta</span>
</p>
<p style="font-size: 10px;">
<span style="color: #999; font-size: 10px;">
<a href="https://uptimerobot.user.com/emails/unsubscribe/4uwjdp/173087/">Unsubscribe</a></span>
</p>
</td>
</tr>
</table>
</td>
</tr>
</table>
<img alt="" src="https://uptimerobot.user.com/emails/open/187/"/></body>
</html>

```

### Additional contract requirements

- Rendering an email with imbricated (nested) tables, where the outer table's
  row carries CSS styling, using the options `--colour --css --ignore-css-colour`
  must produce output that contains the email's text content; it must not
  produce empty output.
