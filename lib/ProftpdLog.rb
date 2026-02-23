# coding: utf-8
#

#
#  Proftpd アクセスlog解析
#

require 'optparse'
require 'sqlite3'
require 'date'
require 'thread'


class Ldata

  attr_accessor :pid, :time, :cmd, :path, :stat, :type
  attr_accessor :base, :topdir, :subdir, :linkPath, :idPath
  attr_accessor :len, :delMark, :timeS, :chkMark

  @@topdirs = TargetDir.map {|tmp| File.basename( tmp ) }

  def initialize( pid: nil, time:  nil, cmd: nil, path: nil, stat: nil, type: nil )
    @pid = pid                  # プロセスID
    @time = time                # 時刻
    @cmd  = cmd                 # 
    @path = path                # ファイルのpath
    @stat = stat                # ftp status
    @type = type                # open/close or short/long
    @len  = nil                 # open - close の秒数
    @delMark = {}               # 削除フラグ
    @chkMark = false            # ?
    @idPath = nil
    @timeS = @time.strftime("%T") if @time != nil
  end

  def makePath()
    return File.join( @topdir,@subdir, @base )
  end
  
  def adj()
    begin
      if @path != nil 
        (tmp, @base )   = File.split( @path )
        (tmp, @subdir ) = File.split( tmp )
        (tmp, @stat )   = File.split( tmp )
        (tmp, @topdir ) = File.split( tmp )
        @linkPath = File.join( OutputDir, @topdir,@stat,@subdir,@base )

        # xfer.log のpath は、空白が "_" に置換されているので一致を見るため。
        @idPath =  FileListUp.new.windowsForbid(  makePath() )
        @idPath = @idPath.gsub(/ /,"_").gsub(/_+/,"_")
      end

    rescue
      print( "Error:" )
      exit
    end
    return self
  end

  def print( str )
    printf("\n%s %s %s\n","-" * 10, str, "-" * 10 )
    pp self
  end

end


class ProftpdLog

  def initialize( )
    @filesize   = {}            # log のファイルサイズ(rotate検出用)
    @sleepT     = 1             # thread ループの sleep時間
    @timeLimit  = Time.now.to_i # log の読み込み開始
    @logWatchTime = 600         # log rotate の監視間隔
    @logfn      = ExteFN
    @step1Q     = Queue.new     # step1: log から、有効成分を抽出
    @step1A     = []
    @step2Q     = Queue.new     # step2: step1 から、open,close の対を抽出
    @step2A     = []            

  end

  ## 転送結果に特化したカスタムログの定義
  ## time pid status path End-of-session-reason
  # LogFormat download_stats "%{iso8601} %P %s \"%r\" \"%E\""
  # ExtendedLog /var/log/proftpd/download.log READ,EXIT download_stats


  def putsErr( e )
    Log::puts( e.backtrace.first + ": #{e.message} (#{e.class})", 0 )
    e.backtrace[1..-1].each { |m| Log::puts("\tfrom #{m}",0) }
    exit
  end

  #
  # 時間の変換
  #
  def timeConv( date, time )
    timeS = date + " " + time + " " 
    dt = DateTime.parse( timeS )
    if TimeOffset == "JST"
      time = dt.new_offset( TimeOffset ).to_time
      time -= 9 * 3600
    else
      time = dt.to_time
    end
    return time
  end

  #
  #  スレッドを起こして、その中でループ
  #
  def threadLoop()
    Thread.new() do |th|
      while true
        begin
          yield
        rescue => e
          putsErr( e )
        end
      end
    end
  end
  
  #
  #  ftp 用 メインルーチン
  #
  def readLog_start( outQ )

    unless test( ?f, @logfn )
      Log::puts("log file not found #{@logfn}",0)
      exit
    end

    # log ファイル から 転送開始、終了の検出
    cmd1 = Queue.new            # logrotate時のrestart命令
    threadLoop() { step1( cmd1, @step1Q ) }

    #  step1 から、アクションを生成
    threadLoop() { step2( @step1Q, outQ ) }
    
    threadLoop() do                
      sleep( @logWatchTime )    # log rotate の監視
      log_watch( cmd1 )
    end

  end

  #
  # log rotate の監視
  #
  def log_watch( cmd1 )
    Log::puts("log_watch() start",4)
    if test( ?f, @logfn )
      @filesize[ @logfn ] ||= -1 
      tmp = File.size( @logfn )
      if tmp < @filesize[ @logfn ]
        @timeLimit = Time.now.to_i
        Log::puts("log rotate #{Time.now.to_s}",0)
        cmd1.push(:stop)
        @filesize = {}
      else
        @filesize[ @logfn ] = tmp
      end
    end
  end

  #
  #  削除の印を立てる
  #
  def delMark( ary, id, n, count=2 )
    count.times do |m|
      ary[n+m].delMark[id] = true
    end
  end
  
  #
  #  削除の印を立てる
  #
  def delMark2( p1, p2, id )
    p1.delMark[id] = true
    p2.delMark[id] = true
  end

  
  #
  #   step1: ftpd のログの解析
  #   
  def step1( cmdQ, outQ )
    #Log::puts("step1() start",4)

    @step1_pid ||= {}
    count = 0
    if test( ?f, @logfn )
      File.open( @logfn, "r") do |fp|
        while true
          if (line = fp.gets()) != nil
            time = stat = pid = cmd = path = arg = nil

            # 2026-02-14 09:29:56,389 2135198 RETR 426 "fname.mp4" ""
            # 2026-02-08 20:12:23,702 4034445 EXIT - "" "Read EOF from client"
            if line =~ /^([\d\-]+) ([\d\:\,]+) (\d+) (\w+) (.*)/
              time = timeConv( $1, $2 )
              pid = $3.to_i
              cmd = $4
              arg = $5
              if cmd == "RETR" and arg =~ /(\d+) \"(.*?)\"/
                stat = $1
                path = $2
              end
            end

            next if time == nil or time.to_i < @timeLimit
            next if pid == nil
            
            if cmd == "RETR" and stat == "226"
              if @step1_pid[ pid ] == nil
                Log::puts("step1: open  #{pid} #{path}",3)
                tmp = Ldata.new( pid: pid, path: path, time: time )
                tmp.adj()
                @step1_pid[ pid ] = tmp
                $nowPlay = tmp.idPath
              end
            elsif cmd == "EXIT"
              if @step1_pid[ pid ] != nil
                Log::puts("step1: close #{pid} #{stat}",3)
                tmpS = @step1_pid[ pid ]
                tmpE = Ldata.new( pid: pid, time: time, stat: stat )
                len = ( tmpE.time - tmpS.time ).to_f
                if len < 3.0 # 3秒以下は捨てる
                  Log::puts("step1: short skip #{pid} #{len}",3)
                  @step1_pid.delete( pid )
                  $nowPlay = nil
                  next
                end
                tmpS.type = len > DoneTime ? :long : :short
                tmpS.len  = len
                tmpS.time  = tmpE.time
                tmpS.adj()
                outQ << tmpS
                @step1_pid.delete( pid )
                $nowPlay = nil
                Log::puts("step1: add step2 #{tmpE.base} #{tmpE.timeS} - #{tmpS.timeS} = #{len} #{tmpS.type.to_s}", 3)
              end
            end
          else
            sleep( @sleepT )
            if count > 60

              unless cmdQ.empty? # log rotate
                tmp = cmdQ.pop
                return if tmp == :stop
              end

              now = Time.now
              @step1_pid.each_pair do |k,v| # 古いものは捨てる
                if ( now - v.time ) > ( 6 * 3600 )
                  Log::puts("step1 old #{v.base} #{v.timeS}",3)
                  @step1_pid.delete( k )
                end
              end
              count = 0
            else
              count += 1
            end
          end
        end
      end
    end
  end

  #
  #  キャンセルの為の short アクセスがあるか check
  #
  def shortChk2?( prev, id )
    @step2A.each do |tmp|
      if tmp.idPath == prev.idPath and tmp.type == :short
        if tmp.time > prev.time
          tmp.delMark[id] = true
          #Log::puts("shortChk2?() #{tmp.base} #{tmp.timeS}",3)
          return true
        end
      end
    end
    false
  end


  def dumpA( head, data, id )
    @mutex ||= Mutex.new
    if $opt.debug == true
      if data.size > 0
        fname = sprintf("%d.log",head )
        @mutex.synchronize do
          File.open( fname, "a" ) do |fp|
            fp.puts("-" * 10 )
            data.each do |tmp|
              timeS = tmp.time.strftime("%T")
              if head == 1
                type = tmp.cmd
              else
                type = tmp.type == nil ? "" : tmp.type.to_s
              end
              del = tmp.delMark[id] == true ? "@" : " "
              fp.printf( "%s%s> %s %d %-5s %s\n",
                         head.to_s,del,timeS, tmp.pid, type, tmp.idPath )
            end
            fp.flush()
          end
        end
      end
    end
  end
  
  #
  # step2: アクションを生成
  #
  def step2( inQ, outQ )

    id = :step2
    oldSize = 0
    while true
      @step2A << inQ.pop unless inQ.empty?
      if oldSize != @step2A.size
        dumpA( 3, @step2A, id )
        oldSize = @step2A.size
      end
      
      now = Time.now
      prev = nil
      @step2A.each_with_index do |tmp,n|
        if tmp.len > DoneTime and ( now - tmp.time ) > FlipDelay
          if shortChk2?( tmp, id ) == true # キャンセル？
            Log::puts("step2: shortChk2?() true #{tmp.base} #{tmp.timeS}",3)
            tmp.delMark[ id ] = true
          else
            Log::puts("step2: ok #{tmp.base} #{tmp.timeS}",3)
            tmp.delMark[ id ] = true
            outQ.push( tmp )
            next
          end
        else
          if $opt.debug == true
            time = now - tmp.time
            if ( time.to_i % 10 ) == 0
              Log::puts("step2: wait #{@step2A.size} #{(time).to_i}",3)
            end
          end
        end
        if prev != nil
          if prev.type == :short and tmp.type == :short
            if tmp.idPath == prev.idPath
              if ( tmp.time - prev.time ).abs < DoneTime
                delMark2( tmp, prev, id )
                outQ.push( tmp )
                Log::puts("step2: double add #{tmp.base} #{tmp.timeS}",3)
              end
            end
          end
        end
        if ( now - tmp.time ) > ( FlipDelay * 5 ) # 古くなったものは捨てる
          Log::puts("step2: old del #{tmp.base} #{tmp.timeS}",3)
          tmp.delMark[ id ] = true
        end
        prev = tmp
      end

      @step2A.delete_if do |tmp|
        if tmp.delMark[ id ] == true
          #Log::puts("step2: del #{tmp.base} #{tmp.timeS}",3)
          true
        end
      end

      sleep( @sleepT )
    end
  end

end

if $0 == __FILE__
  require_relative 'require.rb'
  $opt = Arguments.new(ARGV)

  pfl = ProftpdLog.new()

  thread.each {|t| t.join() }

end
