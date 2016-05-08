class Bus
  attr_reader :code, :terminal_num, :color, :name, :exit_stop, :time, :midnight, :link

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
end
