require "#{File.expand_path(File.dirname(__FILE__))}/bot.rb"
require "#{File.expand_path(File.dirname(__FILE__))}/bus.rb"

require 'nokogiri'
require 'open-uri'
require 'yaml'
require 'active_support'
require 'active_support/core_ext'
require 'holiday_japan'
require 'redis'
require 'cgi'

class BusBot < Bot
  def self.get_instance(text, trigger_word)
    self.new(text, trigger_word)
  end

  def create_response
    config_bus = YAML.load_file("#{File.expand_path(File.dirname(__FILE__)).sub(/lib\/slack-bot/, 'config')}/bus.yml")
    buses = config_bus['bus_lists'].map { |bus_list| create_buses(bus_list) }

    specified_time = over_date? ? @specified_time.tomorrow : @specified_time

    # TODO: 南浦を除けるようにする
    res_buses = buses.flatten.compact.select { |bus| bus.time > specified_time }.sort_by(&:time)[0...10]

    res_header = "*#{specified_time.strftime('%Y/%m/%d %H:%M')}以降のバス*\n#{config_bus['map_bus_mitaka_image_url']}\n\n"
    res = if res_buses.empty?
            message = '*※これ以降のバスはありません*'
            message += "\n(最終 : #{buses.flatten.max_by(&:time).time.strftime('%H:%M')})" unless buses.flatten.empty?

            [
              {
                text: message,
                mrkdwn_in: ['text']
              }
            ] + buses.flatten.sort_by(&:time)[0...10].map(&:inspect)
          else
            res_buses.map(&:inspect)
          end

    {
      text: res_header,
      attachments: res
    }.to_json
  end

  private

  def initialize(text, trigger_word)
    super

    @specified_time = check_datetime_description

    @date_flag = ''
    # 平日or土曜or日祝を判断
    if HolidayJapan.check(Date.parse(@specified_time.to_s)) || @specified_time.sunday?
      @date_flag = 'snd'
    elsif @specified_time.saturday?
      @date_flag = 'std'
    else
      @date_flag = 'wkd'
    end

    @redis = Redis.new(driver: :hiredis)
  end

  def create_buses(bus_list)
    bus_list['types'].map do |bus_type|
      find_key = "#{bus_list['code']}:#{bus_type['name']}:#{bus_list['terminal_num']}"
      @redis.lrange(find_key, 0, -1).map do |hour_min_midnight|
        hour, minute, mark, link, midnight = hour_min_midnight.split(':')
        midnight = !midnight.nil?
        specified_time = %w(00 01 02).include?(hour) ? @specified_time.tomorrow : @specified_time

        bus_time = Time.new(specified_time.year, specified_time.month, specified_time.day, hour)
        if over_date?
          # over_date(specified_timeが00時以降)の時
          # 00時未満の場合はnext
          # 00時以降&指定時間より前のhourの場合はnext
          next if !%w(00 01 02).include?(hour) || bus_time <= (@specified_time - 1.hour)
        else
          # over_dateでない時
          # 指定時間より前のhourの場合はnext
          next if bus_time <= (@specified_time - 1.hour)
        end

        Bus.new(
          bus_list,
          bus_type,
          mark,
          bus_time + minute.to_i.minutes,
          midnight,
          CGI.unescape(link)
        )
      end
    end
  end

  def check_datetime_description
    now = Time.now
    unless @text.strip.sub(/#{@trigger_word}/, '').empty?
      year, month, day = if @text.match(/(一昨日|昨日|今日|明日|明後日)/)
                           ymd = now + (%w(一昨日 昨日 今日 明日 明後日).index($1) - 2).days
                           [ymd.year, ymd.month, ymd.day]
                         elsif @text.match(/(\d{4}?)\/?(\d{1,2})\/(\d{1,2})/)
                           $1.empty? ? [now.year, $2, $3] : [$1, $2, $3]
                         else
                           [now.year, now.month, now.day]
                         end
      hour, minute = @text.match(/(\d{1,2}):(\d{2})/) ? [$1, $2] : [now.hour, now.min]

      time = Time.new(year, month, day, hour, minute)

      # 00:00〜02:59の場合は前の日とする
      between_0_and_2?(hour.to_i) ? time.yesterday : time
    else
      # 00:00〜02:59の場合は前の日とする
      between_0_and_2?(now.hour.to_i) ? now.yesterday : now
    end
  end

  def over_date?
    between_0_and_2?(@specified_time.hour)
  end

  def between_0_and_2?(num)
    [0, 1, 2].include?(num)
  end
end
