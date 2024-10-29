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

  attr_accessor :user, :time, :cmd, :path, :stat, :type
  attr_accessor :base, :topdir, :subdir, :linkPath, :idPath
  attr_accessor :len, :delMark, :timeS, :rcode 

  @@topdirs = TargetDir.map {|tmp| File.basename( tmp ) }

  def initialize( user: nil, time:  nil, cmd: nil, path: nil, stat: nil, rcode: nil  )
    @user = user
    @time = time
    @cmd  = cmd
    @path = path
    @stat = stat
    @rcode = rcode == nil ? 0 : rcode # result code
    @idPath = nil
    @type = nil
    @len  = nil
    @delMark = {}           #  削除フラグ
  end

  def makePath()
    return File.join( @topdir,@subdir, @base )
  end
  
  def adj( type = :link )
    begin
      if @path != nil 
        if type == :link
          (tmp, @base )   = File.split( @path )
          (tmp, @subdir ) = File.split( tmp )
          (tmp, @stat )   = File.split( tmp )
          (tmp, @topdir ) = File.split( tmp )
          @linkPath = File.join( OutputDir, @topdir,@stat,@subdir,@base )
        elsif type == :real
          (tmp, @base )   = File.split( @path )
          (tmp, @subdir ) = File.split( tmp )
          (tmp, @topdir ) = File.split( tmp )
          @stat   = nil
          @linkPath = nil
        end

        # xfer.log のpath は、空白が "_" に置換されているので一致を見るため。
        @idPath =  FileListUp.new.windowsForbid(  makePath() )
        @idPath = @idPath.gsub(/ /,"_").gsub(/_+/,"_")
      end

      @timeS = @time.strftime("%T")
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
    @logfn      = [ ExteFN ]
    @step1Q     = Queue.new     # step1: log から、有効成分を抽出
    @step1A     = []
    @step2Q     = Queue.new     # step2: step1 から、open,close の対を抽出
    @step2A     = []            
    @step3Q     = Queue.new     # step3: step2 から、アクションを生成
    @step3A     = []            
  end

  #LogFormat custom "%u %{iso8601} \"%r\" %s %S %b"
  #ExtendedLog    /var/log/proftpd/extende.log  READ,INFO,MISC,EXIT custom

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

    @logfn.each do |fn|
      unless test( ?f, fn )
        Log::puts("log file not found #{fn}",0)
        exit
      end
    end

    # log ファイル から open,close の検出
    cmd1 = Queue.new            # logrotate時のrestart命令
    threadLoop() { extendeLog(cmd1, @step1Q) }

    # log から、有効成分を抽出、無効成分を削除
    threadLoop() { step1( @step1Q, @step2Q ) }

    # step1 から、open,close の対を抽出
    threadLoop() { step2( @step2Q, @step3Q ) }

    # step2 から、アクションを生成
    threadLoop() { step3( @step3Q, outQ ) }

    threadLoop() do                
      sleep( @logWatchTime )    # log rotate の監視
      log_watch( cmd1 )
    end

  end

  #
  # log rotate の監視
  #
  def log_watch(cmd1 )
    Log::puts("log_watch() start",4)
    @logfn.each do |fname|
      if test( ?f, fname )
        @filesize[ fname ] ||= -1 
        tmp = File.size( fname )
        if tmp < @filesize[ fname ]
          @timeLimit = Time.now.to_i
          Log::puts("log rotate #{Time.now.to_s}",0)
          cmd1.push(:stop)
          @filesize = {}
        else
          @filesize[ fname ] = tmp
        end
      end
    end
  end

  #
  #  削除の印を立てる
  #
  def delMark( ary, id, n )
    ary[n].delMark[id] = true
    ary[n+1].delMark[id] = true
  end
  
  #
  #  削除の印を立てる
  #
  def delMark2( p1, p2, id )
    p1.delMark[id] = true
    p2.delMark[id] = true
  end
  
  #
  #  log ファイル open,close の検出
  #    SIZE の直後に RETR が来たら open
  #    RETR の直後に QUIT or "_" が来たら close
  #   
  def extendeLog( cmdQ, outQ )
    Log::puts("extendeLog() start",4)

    last = nil
    if test( ?f, ExteFN )
      File.open( ExteFN, "r") do |fp|
        while true
          if (line = fp.gets()) != nil
            if line =~ /^(.*?) ([\d\-]+) (.*?) (.*)/
              user = $1
              time = timeConv( $2, $3 )
              val = $4
              next if time.to_i < @timeLimit
              next if user == "-"

              if val =~ /\"(RETR|SIZE)\s(.*?)\" (\d+)/
                cmd = $1
                fname = $2
                rcode = $3.to_i
                tmp = Ldata.new( user: user, path: fname, cmd: cmd, time: time, rcode: rcode )
                tmp.adj( :link )
                outQ << tmp
              elsif val =~ /^\"QUIT\" /        # 無視
                # NOP
              elsif val =~ /^\"\" - \"-\"/     # 終端
                tmp = Ldata.new( user: user, cmd: :fin, time: time ).adj
                outQ << tmp
              end
            end
          else
            sleep( @sleepT )
            unless cmdQ.empty?
              tmp = cmdQ.pop
              return if tmp == :stop
            end
          end
        end
      end
    else
      sleep( @sleepT * 10 )
    end
  end


  #
  #  ファイルがopen中かチェック
  #
  def openChk2?( idPath )
    @step2A.each do |tmp|
      if tmp.idPath == idPath and tmp.type == :open
        return true
      end
    end
    false
  end

  #
  #  short アクセスがあるか check
  #
  def shortChk2?( prev, id )
    @step3A.each do |tmp|
      if tmp.idPath == prev.idPath and tmp.type == :short
        if tmp.time > prev.time
          tmp.delMark[id] = true
          Log::puts("shortChk2?() #{tmp.base} #{tmp.timeS}",3)
          return true
        end
      end
    end
    false
  end


  def dumpA( head, data )
    @mutex ||= Mutex.new
    if $opt.debug == true
      if data.size > 0
        @mutex.synchronize do
          Log::puts("-" * 10,5 )
          data.each do |tmp|
            timeS = tmp.time.strftime("%T")
            str = tmp.type == nil ? tmp.cmd : tmp.type
            Log::puts(sprintf( "%s> %s %-6s %s",head,timeS, str,tmp.base ),5 )
          end
        end
      end
    end
  end
  
  #
  # step3: step2 から、アクションを生成
  #
  def step3( inQ, outQ )
    id = :step3
    oldSize = 0
    while true
      @step3A << inQ.pop unless inQ.empty?
      if oldSize != @step3A.size
        dumpA( "3", @step3A )
        oldSize = @step3A.size
      end
      
      now = Time.now
      prev = nil
      @step3A.each_with_index do |tmp,n|
        if tmp.len > DoneTime and ( now - tmp.time ) > FlipDelay
          if shortChk2?( tmp, id ) == true
            Log::puts("step3 shortChk2?() true #{tmp.base} #{tmp.timeS}",3)
            tmp.delMark[ id ] = true
          elsif openChk2?( tmp.idPath ) == true
            Log::puts("step3 openChk2?() true #{tmp.base} #{tmp.timeS}",3)
            tmp.delMark[ id ] = true
          else
            Log::puts("step3 ok #{tmp.base} #{tmp.timeS}",3)
            tmp.delMark[ id ] = true
            outQ.push( tmp )
            next
          end
        else
          if $opt.debug == true
            time = now - tmp.time
            if ( time.to_i % 10 ) == 0
              Log::puts("step3 wait #{@step3A.size} #{(time).to_i}",3)
            end
          end
        end
        if prev != nil
          if prev.type == :short and tmp.type == :short
            if tmp.idPath == prev.idPath
              if ( tmp.time - prev.time ).abs < DoneTime
                delMark2( tmp, prev, id )
                outQ.push( tmp )
                Log::puts("step3 double add #{tmp.base} #{tmp.timeS}",3)
              end
            end
          end
        end
        if ( now - tmp.time ) > ( FlipDelay * 5 ) # 古くなったものは捨てる
          Log::puts("step3 old #{tmp.base} #{tmp.timeS}",3)
          tmp.delMark[ id ] = true
        end
        prev = tmp
      end

      @step3A.delete_if do |tmp|
        if tmp.delMark[ id ] == true
          Log::puts("step3 del #{tmp.base} #{tmp.timeS}",3)
          true
        end
      end

      sleep( @sleepT )
    end
  end

  #
  #  対応する close を探す
  #
  def step2_find( ary, target )
    ary.each_with_index do |tmp, n |
      if tmp.time > target.time
        if tmp.type == :close
          if tmp.idPath == target.idPath
            return n
          end
        end
      end
    end
    return nil
  end
  
  #
  # step2: step1 から、open,close の対を抽出
  #
  def step2( inQ, outQ )
    id = :step2
    while ret = inQ.pop
      @step2A << ret
      dumpA( "2", @step2A )
      
      now = Time.now
      @step2A.each_with_index do |tmp1,n|
        break if @step2A[n+1] == nil

        if tmp1.type == :open
          if ( m = step2_find( @step2A, tmp1 )) != nil
            tmp2 = @step2A[m]
            len = tmp2.time - tmp1.time
            if len > 2      # 2秒以上を登録
              Log::puts("step2 add step3 #{tmp1.base} #{tmp2.timeS} - #{tmp1.timeS} = #{len}",3)
              tmp2.type = len > DoneTime ? :long : :short
              tmp2.len  = len
              outQ << tmp2
              delMark2( tmp1, tmp2, id )
            else
              Log::puts("step2 ignore #{tmp1.base} #{tmp2.timeS} - #{tmp1.timeS} = #{len}",3)
              delMark2( tmp1, tmp2, id )
            end
          end
        end
        if ( now - tmp1.time ) > 3600 * 3 # 古くなったものは捨てる
          Log::puts("step2 old #{tmp1.base} #{tmp1.timeS}",3)
          tmp1.delMark[id] = true
        end
      end
      @step2A.delete_if do |tmp|
        if tmp.delMark[id] == true
          Log::puts("step2 del #{tmp.base} #{tmp.timeS}",3)
          true
        end
      end
    end
  end

  #
  #  Queue に追加
  #
  def pushQ( type, data, queue )
    data.type = type
    Log::puts( sprintf("%5s  #{data.idPath} #{data.timeS}",type.to_s),3)
    queue << data
  end
    

  #
  #  step1: log から、有効成分を抽出、無効成分を削除
  #
  def step1( inQ, outQ )
    id = :step1
    while ret = inQ.pop
      @step1A << ret
      dumpA( "1", @step1A )

      @step1A.each_with_index do |tmp,n|
        break if @step1A[n+1] == nil
        next if tmp.delMark[id] == true

        if @step1A[n].cmd == "SIZE" and @step1A[n+1].cmd == "RETR"
          if @step1A[n].idPath == @step1A[n+1].idPath
            pushQ( :open, @step1A[n], outQ )
            delMark( @step1A, id, n )
          end
        elsif @step1A[n].cmd == "RETR" and @step1A[n+1].cmd == :fin
          @step1A[n].time = @step1A[n+1].time
          @step1A[n].timeS = @step1A[n+1].timeS
          pushQ( :close, @step1A[n], outQ )
          @step1A.clear
        elsif @step1A[n].cmd == "SIZE" and @step1A[n+1].cmd == :fin
          if @step1A[n].rcode == 550
            delMark( @step1A, id, n )
          end
        end
      end
      @step1A.delete_if do |tmp|
        if tmp.delMark[id] == true
          Log::puts("extendeLog del #{tmp.base} #{tmp.timeS}",3)
          true
        end
      end
    end
  end


  
end

if $0 == __FILE__
  require_relative 'require.rb'
  $opt = Arguments.new(ARGV)

  pfl = ProftpdLog.new()

  thread.each {|t| t.join() }

end
