class Bot
  def initialize(text)
    @text = text
    # TODO: textからtimeを設定できるように
    @specified_time = Time.now
  end

  def over_date?
    [0, 1, 2].include?(@specified_time.hour)
  end
end
