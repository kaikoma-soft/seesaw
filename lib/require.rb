# coding: utf-8


#
#  config の読み込み
#
files = [ ]
files << ENV["SEESAW_CONF"] if ENV["SEESAW_CONF"] != nil
files << ENV["HOME"] + "/.config/seesaw/config.rb"
files.each do |cfg|
  if test( ?f, cfg )
    require cfg
    ConfigPath = cfg
    break
  end
end
raise "counfig not found" if Object.const_defined?(:BaseDir) != true


require_relative 'Const.rb'
require_relative 'Arguments.rb'
require_relative 'DB.rb'
require_relative 'DBKeyval.rb'
require_relative 'DBTable.rb'
require_relative 'DBTarget.rb'
require_relative 'FileListUp.rb'
require_relative 'Log.rb'
require_relative 'SmbLog.rb'

