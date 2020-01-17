#!/usr/bin/ruby
# -*- coding: utf-8 -*-


module Log
  def puts( str, level = 0 )

    if $opt.logLevel > level
      now = Time.now
      txt = sprintf("%s: %s\n",now.strftime("%H:%M:%S"),str)
      Kernel.puts( txt ) if $opt.background == false
      File.open( LogFname, "a") do |fp|
        fp.puts( txt )
        fp.sync
      end
    end

    if test( ?f, LogFname )
      if File.size( LogFname ) > LogRotateSize
        File.rename( LogFname, LogFname + ".old" )
      end
    end
    
  end
  module_function :puts
  
end


