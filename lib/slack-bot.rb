require "#{File.expand_path(File.dirname(__FILE__))}/slack-bot/bus_bot"
require 'rubygems'
require 'sinatra/base'
require 'json'

class SlackBot < Sinatra::Base
  post '/slack' do
    bot = get_instance

    content_type :json
    bot.create_response
  end

  def get_instance
    case params['trigger_word']
    when 'バス', 'ばす', 'bus', 'バ', 'ば', 'b' then
      BusBot.new(params['text'], params['trigger_word'])
    end
  end
end
