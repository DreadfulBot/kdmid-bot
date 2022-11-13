# Kdmid bot

Checks ability to make an appointment to consul

Original repository here - https://gitfront.io/r/accessd/6GgvFZvbdTTM/kdmid-bot/ 

## Setup

Register on https://2captcha.com/ and get API key.

Create .env file and fill variables:

    $ cp .env.example .env

### Docker

    $ bin/build && bin/start

Run bot with:

    $ bin/bot

**How to see the browser?**

View the firefox node via VNC (password: secret):

    $ open vnc://localhost:5900

### Locally

Install ruby 3.1.2 with rbenv for example.

Install browser and driver: http://watir.com/guides/drivers/
You can use firefox with geckodriver.

Setup dependencies:

    $ bundle

Run bot with:

    $ ruby bot.rb

## Issues

Problems with hcaptcha: do not pass it periodically

## Deployments

Example of crontab task, which runs bot each 15 minutes in daytime:

```
15 12-23 * * * cd /root/docker/kdmid-bot; ./bin/start.sh && ./bin/bot.sh 2>&1 | /usr/bin/logger -t kdmid-bot
```