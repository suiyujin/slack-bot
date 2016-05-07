class Bus
  attr_reader :code, :terminal_num, :name, :exit_stop, :time, :midnight

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
