require "#{File.expand_path(File.dirname(__FILE__))}/slack-bot/bot"
require "#{File.expand_path(File.dirname(__FILE__))}/slack-bot/bus"

class BusBot < Bot
  def create_response
    bus = Bus.new
  end
end
