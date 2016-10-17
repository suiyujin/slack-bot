require "#{File.expand_path(File.dirname(__FILE__)).sub(/jobs$/, '')}/bus.rb"

require 'nokogiri'
require 'open-uri'
require 'yaml'
require 'active_support'
require 'active_support/core_ext'
require 'holiday_japan'
require 'redis'

class ScrapeTimetableJob
  def self.run
    new
  end

  private

  def initialize
    @specified_time = Time.now

    @date_flag = ''
    # 平日or土曜or日祝を判断
    if HolidayJapan.check(Date.parse(@specified_time.to_s)) || @specified_time.sunday?
      @date_flag = 'snd'
    elsif @specified_time.saturday?
      @date_flag = 'std'
    else
      @date_flag = 'wkd'
    end

    config_bus = YAML.load_file("#{File.expand_path(File.dirname(__FILE__)).sub(/lib\/slack-bot\/jobs/, 'config')}/bus.yml")
    buses = config_bus['bus_lists'].map { |bus_list| scrape_timetable(bus_list) }.flatten

    redis = Redis.new(driver: :hiredis)
    buskeys = redis.keys('バス:*')
    redis.del(buskeys) unless buskeys.empty?

    buses.each { |bus| redis.rpush(bus.redis_key, bus.redis_value) }
  end

  def scrape_timetable(bus_list)
    buses = []

    url = "http://transfer.navitime.biz/odakyubus/pc/diagram/BusDiagram?orvCode=#{bus_list['orv_code']}&course=#{bus_list['course']}&stopNo=#{bus_list['stop_no']}&date=#{@specified_time.strftime('%Y-%m-%d')}"

    Nokogiri::HTML(open(url)).xpath('//div[@id="diagram-pannel"]/table/tr[@class="l2"]/th[@class="hour"]').each do |hour_list|
      hour = remove_tab_and_newline(hour_list.text)

      bus_time = Time.new(@specified_time.year, @specified_time.month, @specified_time.day, hour)

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
