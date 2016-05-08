require "#{File.expand_path(File.dirname(__FILE__))}/bot.rb"
require "#{File.expand_path(File.dirname(__FILE__))}/bus.rb"

require 'nokogiri'
require 'open-uri'
require 'yaml'
require 'active_support'
require 'active_support/core_ext'
require 'holiday_japan'

class BusBot < Bot
  def create_response
    @specified_time = check_datetime_description

    # 平日or土曜or日祝を判断
    @date_flag = ''
    if HolidayJapan.check(Date.parse(@specified_time.to_s)) || @specified_time.sunday?
      @date_flag = 'snd'
    elsif @specified_time.saturday?
      @date_flag = 'std'
    else
      @date_flag = 'wkd'
    end

    bus_lists = YAML.load_file("#{File.expand_path(File.dirname(__FILE__)).sub(/lib\/slack-bot/, 'config')}/bus.yml")['bus_lists']
    buses = []
    bus_lists.each do |bus_list|
      buses << scrape_timetable(bus_list)
    end
    # TODO: 南浦を除けるようにする
    res = buses.flatten.select { |bus| bus.time > @specified_time }.sort_by(&:time)[0...10]

    headline_time = over_date? ? @specified_time.tomorrow : @specified_time
    res_str = "*#{headline_time.strftime('%Y/%m/%d %H:%M')}以降のバス*\n\n"
    res_str += if res.empty?
                message = '※これ以降のバスはありません'
                unless buses.flatten.empty?
                  message += "\n(最終 : #{buses.flatten.max_by(&:time).time.strftime('%H:%M')})"
                end
                message
              else
                res.map do |bus|
                  bus_str = "#{bus.time.strftime('%H:%M')} [#{bus.code}] #{bus.name}\n(#{bus.terminal_num}番乗り場 / 降車：#{bus.exit_stop})"
                  bus_str += "\n※深夜バス（倍額）" if bus.midnight
                  bus_str
                end.join("\n\n")
              end

    {text: res_str}.to_json
  end

  def scrape_timetable(bus_list)
    buses = []

    orv_code = bus_list['orv_code']
    course = bus_list['course']
    stop_no = bus_list['stop_no']

    url = "http://transfer.navitime.biz/odakyubus/pc/diagram/BusDiagram?orvCode=#{orv_code}&course=#{course}&stopNo=#{stop_no}&date=#{@specified_time.strftime('%Y-%m-%d')}"

    page = Nokogiri::HTML(open(url))
    page.xpath('//div[@id="diagram-pannel"]/table/tr[@class="l2"]/th[@class="hour"]').each do |hour_list|
      hour = remove_tab_and_newline(hour_list.text)

      bus_time = Time.new(@specified_time.year, @specified_time.month, @specified_time.day, hour)
      if over_date?
        # over_date(specified_timeが00時以降)の時
        # 00時未満の場合はnext
        # 00時以降&指定時間より前のhourの場合はnext
        if !%w(00 01 02).include?(hour) || bus_time <= (@specified_time - 1.hour)
          next
        end
      else
        # over_dateでない時
        # 指定時間より前のhourの場合はnext
        next if bus_time <= (@specified_time - 1.hour)
      end

      buses << get_date_list(hour_list).xpath('div[@class="diagram-item"]').map do |minute|
        midnight = false

        mark = remove_tab_and_newline(minute.xpath('div[@class="mark"]/div[@class="top"]').text)
        if mark.match(/\A深(.)/)
          midnight, mark = [true, $1]
        end

        mm = remove_tab_and_newline(minute.xpath('div[@class="mm"]').text)

        time = bus_time + mm.to_i.minutes

        bus_type = bus_list['types'].find { |bus| bus['mark'] == mark }

        Bus.new(
          bus_list['code'],
          bus_list['terminal_num'],
          bus_type,
          mark,
          time,
          midnight
        )
      end
    end
    buses
  end

  private

  def check_datetime_description
    now = Time.now
    unless @text.strip.sub(/#{@trigger_word}/, '').empty?
      year, month, day = if @text.match(/(\d{4}?)\/?(\d{1,2})\/(\d{1,2})/)
                           $1.empty? ? [now.year, $2, $3] : [$1, $2, $3]
                         else
                           [now.year, now.month, now.day]
                         end
      hour, minute = @text.match(/(\d{2}):(\d{2})/) ? [$1, $2] : [now.hour, now.min]

      # 00:00〜02:59の場合は前の日とする
      day = day.to_i - 1 if [0, 1, 2].include?(hour.to_i)

      Time.new(year, month, day, hour, minute)
    else
      now
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
    [0, 1, 2].include?(@specified_time.hour)
  end
end
