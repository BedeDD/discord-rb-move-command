# discord-rb-move-command

This repo is a bot that allows you to fake the move of messages from on channel to another on your discord server.

# Prerequisites

1. Register a new app at [Discord Developer Portal](https://discord.com/developers/applications)
2. Visit https://discord.com/developers/applications/YOUR_APP_ID/oauth2 to get OAuth data
3. Connect your bot to your server.

# Getting started

1. Clone this repo `git clone https://github.com/BedeDD/discord-rb-move-command.git`
2. Copy your `client_id` to your config.yml
3. Copy your `client_secret` to your config.yml
4. Insert your user roles with move permission in your config.yml
5. In Terminal
  5.1. Install bundler `gem install bundler`
  2. Install the bundle `bundle install`
  3. Run the script `ruby move_bot.rb`
