require "#{File.expand_path(File.dirname(__FILE__))}/slack-bot/bus_bot"
require 'rubygems'
require 'sinatra/base'
require 'json'

class SlackBot < Sinatra::Base
  post '/slack' do
    bot = case params['trigger_word']
    when 'バス', 'ばす', 'bus', 'バ', 'ば', 'ハ', 'は', 'b' then
      BusBot::get_instance(params['text'], params['trigger_word'])
    end

    content_type :json
    bot.create_response
  end
end
