

class ReadConfig

  attr_reader :background
  attr_reader :flip
  attr_reader :debug
  attr_reader :config

  def initialize( file = nil )
    @config = 'config.rb' if file != nil

    
  end


end
