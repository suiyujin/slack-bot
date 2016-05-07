class Bus
  attr_reader :time

  def initialize(code, terminal_num, bus_type, mark, time, midnight)
    @code = code
    @terminal_num = terminal_num
    @name = bus_type['name']
    @exit_stop = bus_type['exit_stop']
    @mark = mark
    @time = time
    @midnight = midnight
  end
end
