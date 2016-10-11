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

    now = Time.now
    @specified_time = check_datetime_description(now)

    @use_redis_flag = if between_0_and_2?(now.hour)
                        if between_0_and_2?(@specified_time.hour)
                          @specified_time.day == now.day
                        else
                          @specified_time.day == now.yesterday.day
                        end
                      else
                        if between_0_and_2?(@specified_time.hour)
                          @specified_time.day == now.tomorrow.day
                        else
                          @specified_time.day == now.day
                        end
                      end

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
    @use_redis_flag ? from_redis(bus_list) : scrape_timetable(bus_list)
  end

  def scrape_timetable(bus_list)
    buses = []

    url = "http://transfer.navitime.biz/odakyubus/pc/diagram/BusDiagram?orvCode=#{bus_list['orv_code']}&course=#{bus_list['course']}&stopNo=#{bus_list['stop_no']}&date=#{@specified_time.strftime('%Y-%m-%d')}"

    Nokogiri::HTML(open(url)).xpath('//div[@id="diagram-pannel"]/table/tr[@class="l2"]/th[@class="hour"]').each do |hour_list|
      hour = remove_tab_and_newline(hour_list.text)
      specified_time = %w(00 01 02).include?(hour) ? @specified_time.tomorrow : @specified_time

      bus_time = Time.new(specified_time.year, specified_time.month, specified_time.day, hour)

      buses << get_date_list(hour_list).xpath('div[@class="diagram-item"]').map do |minute|
        midnight = false

        mark = remove_tab_and_newline(minute.xpath('div[@class="mark" or @class="mark threeString"]/div[@class="top"]').text)
        midnight, mark = [true, $1] if mark.match(/\A深(.+)/)

        Bus.new(
          bus_list,
          bus_list['types'].find { |bus| bus['mark'] == mark },
          mark,
          bus_time + remove_tab_and_newline(minute.xpath('div[@class="mm"]').text).to_i.minutes,
          midnight,
          (URI.parse(url) + minute.xpath('div[@class="mm"]/a/@href').first.value).to_s
        )
      end
    end
    buses
  end

  def from_redis(bus_list)
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

  def check_datetime_description(now)
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

  def get_date_list(hour_list)
    case @date_flag
    when 'wkd' then
      hour_list.next.next
    when 'std' then
      hour_list.next.next.next.next
    when 'snd' then
      hour_list.next.next.next.next.next.next
    end
  end

  def remove_tab_and_newline(text)
    text.gsub(/\t/, '').gsub(/\n/, '')
  end

  def over_date?
    between_0_and_2?(@specified_time.hour)
  end

  def between_0_and_2?(num)
    [0, 1, 2].include?(num)
  end
end
