require "#{File.expand_path(File.dirname(__FILE__))}/slack-bot/bus_bot"
require 'rubygems'
require 'sinatra/base'
require 'pry'
require 'json'

class SlackBot < Sinatra::Base
  before do
    @params = JSON.parse(request.body.read)
  end

  post '/slack' do
    bot = get_instance
    res = bot.create_response

    { message: "Hello, #{@params['name']}!" }.to_json
  end

  def get_instance
    case params['trigger_word']
    when 'バス' then
      BusBot.new(params['text'])
    end
  end
end
