require "#{File.expand_path(File.dirname(__FILE__))}/bot.rb"
require "#{File.expand_path(File.dirname(__FILE__))}/bus.rb"

require 'nokogiri'
require 'open-uri'
require 'yaml'
require 'active_support'
require 'active_support/core_ext'

class BusBot < Bot
  def create_response
    bus_lists = YAML.load_file("#{File.expand_path(File.dirname(__FILE__)).sub(/lib\/slack-bot/, 'config')}/bus.yml")['bus_lists']
    buses = []
    bus_lists.each do |bus_list|
      buses << scrape_timetable(bus_list)
    end
    # TODO: 南浦を除けるようにする
    res = buses.flatten.select { |bus| bus.time > @specified_time }.sort_by(&:time)[0...10]

    # TODO: もうバスが無い場合はメッセージを返す
    res_str = res.map do |bus|
      "#{bus.time.strftime('%H:%M')} [#{bus.code}] #{bus.name}\n(#{bus.terminal_num}番乗り場 / 降車：#{bus.exit_stop})"
    end.join("\n\n")
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

      buses << hour_list.next.next.xpath('div[@class="diagram-item"]').map do |minute|
        midnight = false

        mark = remove_tab_and_newline(minute.xpath('div[@class="mark"]/div[@class="top"]').text)
        if mark.match(/\A深(.)/)
          midnight, mark = [true, $1]
        end

        mm = remove_tab_and_newline(minute.xpath('div[@class="mm"]').text)

        bus_time = bus_time + mm.to_i.minutes

        bus_type = bus_list['types'].find { |bus| bus['mark'] == mark }
        Bus.new(
          bus_list['code'],
          bus_list['terminal_num'],
          bus_type,
          mark,
          bus_time,
          midnight
        )
      end
    end
    buses
  end

  private

  def remove_tab_and_newline(text)
    text.gsub(/\t/, '').gsub(/\n/, '')
  end
end
