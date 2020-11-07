# coding: utf-8
#

#
#  main 
#
require 'rubygems'
require 'sqlite3'
require_relative 'lib/require.rb'

class Main

  def initialize(argv)
    $opt = Arguments.new(argv)
    setTrap()

    unless FileTest.directory?( BaseDir )
      puts("Error: BaseDir(#{BaseDir}) not found")
      exit
    end

  end

  def run()

    # オプションの処理
    if $opt.kill == true
      killPid()
    elsif $opt.refresh == true
      killPid( :USR1 )
    elsif $opt.notyet != nil 
      inverter( :notyet, $opt.notyet )
      exit
    elsif $opt.done != nil 
      inverter( :done, $opt.done )
      exit
    end

    File.open( LockFN, File::RDWR|File::CREAT, 0644) do |fl|
      if fl.flock(File::LOCK_EX|File::LOCK_NB) == false
        puts("Error: #{PNAME} locked\n")
        exit
      end

      # main loop 開始
      if $opt.background == true
        daemonStart{ mainLoop() }
      else
        mainLoop()
      end
    end
    File.unlink( LockFN )
  end

  def mainLoop()
    Log::puts("main loop start")

    File.open( PidFile, "w") do |fp|
      fp.puts( Process.pid  )
    end

    if FileTest.directory?( OutputDir )
      FileUtils.remove_entry( OutputDir, true )
    end

    flu = FileListUp.new()
    flu.find()

    sm = SmbLog.new()

    while true
      sm.readLog()
      ret = sm.fetchCQ()
      if ret.size > 0
        inverter2( ret )
      end
      if sm.reset?()
        sm.reopen()
      end

      flu.find() if ( Time.now - flu.findtime ) > RefreshPeriod

      sa = ( Time.now - sm.acctime )
      wtime = 60
      if sa < 60
        wtime = 2
      elsif sa < 1800
        wtime = 10
      end
      sleep(wtime)
    end
    
  end


  def killPid( type = :TERM )
    if FileTest.exist?( PidFile )
      File.open( PidFile,"r" ) do |fp|
        pid = fp.gets().to_i
        if pid > 0
          begin
            Process.kill( type , pid )
          rescue Errno::ESRCH
          end
          Log::puts("kill #{type} #{pid}")
        end
      end
    end
    exit
  end

  
  #
  #  デーモン化
  #
  def daemonStart( )
    if fork                       # 親
      exit!(0) 
    else                          # 子
      Process::setsid
      if fork                     # 親
        exit!(0) 
      else                        # 子
        Dir::chdir("/")
        File::umask(0)

        STDIN.reopen("/dev/null")
        if $debug == true
          STDOUT.reopen( StdoutM, "w")
          STDERR.reopen( StderrM, "w")
        else
          STDOUT.reopen("/dev/null", "w")
          STDERR.reopen("/dev/null", "w")
        end
        yield if block_given?
      end
    end
  end

  #
  #  オプションからの 強制設定
  #
  def inverter( type, str )
    flu = FileListUp.new()
    reg = Regexp.new( str )
    target = DBTarget.new
    type2 = type == :done ? 1 : 0
    
    DBaccess.new().open do |db|
      db.transaction do
        target.select( db ).each do |r|
          if reg =~ r[:rpath] and type2 != r[:stat] and r[:stat] != 2
            stat = r[:stat] == 0 ? "未->既" : "既->未"
            Log::puts("#{stat} #{r[:rpath]}")

            stat2 = r[:stat] == 0 ? 1 : 0
            if $opt.test == false
              target.update( db, r[:id], stat: stat2 )
              flu.flip( r )
            end
          end
        end
      end
    end
    flu.delEmptyDir( )
  end

  #
  #  smb log 検出からの反転
  #
  def inverter2( r )
    flu = FileListUp.new()
    statStr2 = {}
    StatStr.each_pair { |k,v| statStr2[v] = k }

    data = []
    target = DBTarget.new
    DBaccess.new().open do |db|
      data = target.select( db )
    end

    r.each do |r2|
      if r2 =~ /^(.*?)\/(.*?)\/(.*)/
        topdir = $1
        type = $2
        path = $3
        stat = statStr2[ type ]
        ff   = false
        next if stat == NA
        data.each do |r3|
          if stat == r3[:stat] and path == r3[:rpath] and topdir = r3[:topdir]
            stat2 = stat == 0 ? "未->済" : "済->未"
            Log::puts("#{stat2} #{r3[:rpath]}")
            stat2 = r3[:stat] == 0 ? 1 : 0
            DBaccess.new().open do |db|
              target.update( db, r3[:id], stat: stat2 )
            end
            flu.flip( r3 )
            ff = true
            break
          end
        end
        if ff == false
          Log::puts("Error: inverter2() not found data #{path}" )
        end
      else
        Log::puts("Error: inverter2() not match #{r2}" )
      end
    end
  end

  def signalProc()
    Log::puts("signalProc()")
    flu = FileListUp.new()
    flu.find()
  end
  

  #
  #  signal trap の設置
  #
  def setTrap()
    name = File.basename( $0 )
    Signal.trap( :HUP )  { Log::puts("#{name} :HUP") ; signalProc() }
    Signal.trap( :USR1 ) { Log::puts("#{name} :USR1") ; signalProc() }
  end

  
end



Main.new(ARGV).run if $0 == __FILE__


    
