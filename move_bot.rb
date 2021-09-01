# frozen_string_literal: true

# @author Benjamin "Lampe385" Deutscher <ben@bdeutscher.org>
# credit to discordrb: https://github.com/discordrb/discordrb

#-- in case of problems running this script as a service you may need to uncomment the following three lines
# require 'rubygems'
# require 'bundler/setup'
# Bundler.require(:default)

require 'discordrb'
require 'psych'
require 'open-uri'

# This is the MoveBot driven by disordrb.
# It enables you to 'move' messages between channels on your discord server.
# @example
#   run locally with "ruby move_bot.rb" (end with ctrl + c)
class MoveBot
  attr_reader :bot, :config

  VERSION = '1.0.0'
  COMMAND_PREFIX = '!'
  MESSAGE_URI = 'https://discord.com/channels/SERVER_ID/CHANNEL_ID/MESSAGE_ID'


  # Constructor
  # @return [Discordrb::Commands::CommandBot] new instance of the bot
  def initialize
    @config = Psych.load_file(%W[#{__dir__} config.yml].join('/'))
    @bot = Discordrb::Commands::CommandBot.new(token: @config['auth_token'],
                                               client_id: @config['client_id'],
                                               prefix: COMMAND_PREFIX)
  end

  # call this method to start your bot
  # register new commands INSIDE this method
  def run
    register_version_command
    register_move_command

    # use discordrb to run your bot on your server
    @bot.run
  end

  private

  # Registers the `#{COMMAND_PREFIX}version` command which posts the bots message in reply to your message calling the commend
  def register_version_command
    # getting current version and general info
    @bot.command :version do |event|
      event.message.reply("MoveBot running on Version #{VERSION}")
    end
  end

  # Registers the `#{COMMAND_PREFIX}move` command which lets you "move" a given message from one channel to a given one.
  def register_move_command
    @bot.command :move do |event, message_id, target_channel_id, *reason|
      # to check permission of the command calling user we need to collect their roles on the server
      user_roles = event.user.roles.collect(&:name)

      # permission check - server owner is always allowed to use the command
      return unless [user_roles & @config['mover_roles']].any? || event.user.owner?

      # extract the target channels id from the command message markup
      target_channel_id = target_channel_id.tr('<#>', '').to_i

      # we do not want all plebs to see the actual command calling message
      event.message.delete

      # to post a message in a new channel we need to select it from the available channels on the server
      target_channel = event.channel.server.channels.collect { |chan| chan if chan.id == target_channel_id }.compact&.first

      # the calling user might mistypes the target channels name and we do not want to fail if there is no channel with the given name
      return event.respond("Unkown channel #{target_channel_id}") if target_channel.nil?

      # the bot needs the server id to know where to post the message
      server_id = event.channel.server.id

      # just in case there is no server on the event
      return event.respond('No server found :(') if server_id.nil?

      # get the actual message object by the given message id
      message_to_move = event.channel.message(message_id)

      # the calling user might mistypes the message id and we do not want to fail
      return event.respond(no_message_found_msg) if message_to_move.nil?

      # build the moved message with markup
      target_channel_msg = message_moved_msg(mover: event.message.author,
                                             source_channel: event.channel,
                                             moved_message: message_to_move,
                                             move_reason: reason)

      # this is the actual "move" of the original message a.k.a. repost as bot with quote of original message
      moved_message = target_channel.send_message(target_channel_msg)

      # we want the moved message to disappear
      event.channel.message(message_id).delete

      # users should know where the message is gone
      event.respond(original_message_removed_info(server_id: server_id, target_channel_id: target_channel_id, moved_message: moved_message))
    end

    # Returns the error message that is posted when no message could be found in the channel with the given message id
    # @return [String] the message to post
    def no_message_found_msg
      <<~MSG
        _Unfortunately I cannot find a message with the given message id :(_
      MSG
    end

    # Returns the message that is posted when the message was moved
    # @param mover [Discordrb::User] the user that called the move command
    # @param source_channel [Discordrb::Channel] the channel the command was called from
    # @param moved_message [Discordrb::Message] the message that should be moved
    # @param move_reason [String] the reason the message was moved (can be blank in command call)
    # @return [String] the message to post
    def message_moved_msg(mover:, source_channel:, moved_message:, move_reason:)
      <<~MSG
        _This message was moved here by <@#{mover.id}> from channel <##{source_channel.id}>._
        #{move_reason_msg(move_reason)}
        _<@#{moved_message.author.id}> wrote at #{moved_message.timestamp.strftime("%d.%m.%Y um %H:%M:%S")}_
        #{moved_message_to_quote(moved_message)}
        #{message_moved_attachment_list(moved_message)}
      MSG
    end

    # Formats the moved message to look like a quote in Discord markup
    # @param moved_message [Discordrb::Message] the message that was moved
    # @return [String] the quoted message
    def moved_message_to_quote(moved_message)
      return '(there was no message content - did you move an attachment without text?)' unless moved_message&.content.nil?

      moved_message.content.split("\n").join("\n> ").prepend("\n> ")
    end

    # Returns the message part that provides the reason of the move
    # @param reason [String] the reason the message was moved (can be blank in command call)
    # @return [String] the message to post
    def move_reason_msg(reason)
      # since the reason is optional we need to check whether it was given by the calling user or not
      reason&.any? ? "**Reason provided:**: _#{reason.join(' ')}_\n" : ''
    end

    # Returns a list of links of the attachments of the original message
    # @param moved_message [Discordrb::Message] the message that was moved
    # @return [String] the message part with the links to the original message attachments
    def message_moved_attachment_list(moved_message)
      # no attachments no links
      return '' if moved_message.attachments.empty?

      link_list = moved_message.attachments.collect { |attachment| "- #{attachment.url}" }.join("\n")
      <<~MSG

        Attachments of the original message:
        #{link_list}
      MSG
    end

    # Returns the message to redirect users to the new message int the target channel
    # @param server_id [Integer, String] the servers id
    # @param target_channel_id [Integer] the targe channels id
    # @param moved_message [Discordrb::Message] the moved message
    def original_message_removed_info(server_id:, target_channel_id:, moved_message:)
      new_message_uri = MESSAGE_URI.gsub('SERVER_ID', server_id.to_s).gsub('CHANNEL_ID', target_channel_id.to_s).gsub('MESSAGE_ID', moved_message.id.to_s)
      <<~MSG
        _This message was moved and can now be found here:_
        #{new_message_uri}
      MSG
    end
  end
end

bot = MoveBot.new
bot.run
