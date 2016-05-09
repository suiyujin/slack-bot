class Bus
  attr_reader :time, :inspect

  def initialize(code, terminal_num, color, bus_type, mark, time, midnight, link)
    @code = code
    @terminal_num = terminal_num
    @color = color
    @name = bus_type['name']
    @exit_stop = bus_type['exit_stop']
    @mark = mark
    @time = time
    @midnight = midnight
    @link = link
  end

  def inspect
    text = "( *#{@terminal_num}* 番乗り場 / 降車： *#{@exit_stop}* )"
    text += "\n`※深夜バス(倍額)`" if @midnight
    {
      fallback: "#{@time.strftime('%H:%M')} [#{@code}] #{@name} #{text}",
      title: "#{@time.strftime('%H:%M')} [#{@code}] #{@name}",
      title_link: @link,
      text: text,
      color: @color,
      mrkdwn_in: ['text']
    }
  end
end
