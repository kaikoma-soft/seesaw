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
  attr_accessor :len, :delMark, :timeS, :rcode, :chkMark

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
    @chkMark = false
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
  #  extende.log から必要な要素の抽出
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

              if val =~ /\"(RETR|REST)\s(.*?)\" (\d+)/
                cmd = $1
                fname = $2
                rcode = $3.to_i
                tmp = Ldata.new( user: user, path: fname, cmd: cmd, time: time, rcode: rcode )
                tmp.adj( :link )
                outQ << tmp
              elsif val =~ /^\"(EPSV)\" (\d+) /
                cmd = $1
                rcode = $2.to_i
                tmp = Ldata.new( user: user, cmd: cmd, time: time, rcode: rcode  )
                outQ << tmp
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
              code = tmp.rcode == nil ? "" : tmp.rcode.to_s
              fp.printf( "%s%s> %s %-5s %s %s\n",
                         head.to_s,del,timeS, type, code, tmp.base )
            end
            fp.flush()
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
        dumpA( 3, @step3A, id )
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
          #Log::puts("step3 del #{tmp.base} #{tmp.timeS}",3)
          true
        end
      end

      sleep( @sleepT )
    end
  end

  #
  #  対応する open/close を探す
  #
  def step2_find( ary, target, type )
    ary.each_with_index do |tmp, n |
      if tmp.type == type
        if tmp.idPath == target.idPath
          return n
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
      dumpA( 2, @step2A, id )
      
      now = Time.now
      @step2A.each_with_index do |tmp1,n|
        next if tmp1.delMark[id] == true
        
        if tmp1.type == :open
          if @step2A[ n+1 ] != nil and @step2A[ n+1 ].type == :open # 重複は削除
            tmp2 = @step2A[n+1]
            sa = ( tmp2.time - tmp1.time ).abs
            if sa < 1.0
              tmp2.delMark[id] = true
              break
            end
          end
        elsif tmp1.type == :close or tmp1.type == :closeD
          m = step2_find( @step2A, tmp1, :open )
          if m != nil
            tmp2 = @step2A[m]
            len = tmp1.time - tmp2.time
            if len < 0
              next
            elsif len > 2      # 3秒以上を登録
              Log::puts("step2: add step3 #{tmp1.base} #{tmp2.timeS} - #{tmp1.timeS} = #{len}",3)
              tmp1.type = len > DoneTime ? :long : :short
              tmp1.len  = len
              outQ << tmp1
              delMark2( tmp1, tmp2, id )
              break
            else
              if tmp1.type == :closeD
                Log::puts("step2: dummy close #{tmp1.base} #{tmp1.timeS}",3)
                tmp1.delMark[id] = true
              else
                Log::puts("step2: ignore #{tmp1.base} #{tmp2.timeS} - #{tmp1.timeS} = #{len}",3)
                delMark2( tmp1, tmp2, id )
                break
              end
            end
          else
            Log::puts("step2: open not found #{tmp1.base} #{tmp1.timeS}",3)
            tmp1.delMark[id] = true
            break
          end
        end
        if ( now - tmp1.time ) > 3600 * 3 # 古くなったものは捨てる
          Log::puts("step2 old #{tmp1.base} #{tmp1.timeS}",3)
          tmp1.delMark[id] = true
        end
      end
      @step2A.delete_if do |tmp|
        if tmp.delMark[id] == true
          #Log::puts("step2 del #{tmp.base} #{tmp.timeS}",3)
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
    Log::puts( sprintf("pushQ(%5s  #{data.idPath} #{data.timeS})",type.to_s),3)
    queue << data
  end
    

  #
  #  キーワードが揃っているかチェック
  #
  def step1sub( ary, n, list, timeLimit = 0.5 )
    endTime = ary[n].time + timeLimit
    ary.each {|v| v.chkMark = false }

    #pp "----" * 4 + list.join(",")
    list.each do |item|
      flag = false
      n.upto( ary.size - 1) do |m|
        next if ary[m].chkMark == true
        #pp ary[m].cmd,item
        if ary[m].cmd == item
          ary[m].chkMark = true
          flag = true
          #printf("%s found\n",item )
          break
        end
        if ary[m].time > endTime
          #printf("%s time out %s \n",item, ary[m].time )
          return false
        end
      end
      if flag == false
        #printf("%s not found\n",item )
        return false
      end
    end
    return true
  end

  #
  #  step1: log から、有効成分を抽出、無効成分を削除
  #
  def step1( inQ, outQ )
    id = :step1
    openCmd = %W( EPSV RETR EPSV REST RETR )
    closeCmd = [ "RETR", :fin ]

    while ret = inQ.pop
      @step1A << ret 
      dumpA( 1, @step1A, id )

      @step1A.each_with_index do |tmp,n|
        next if tmp.delMark[id] == true

        if @step1A[n].cmd == "EPSV" and ( @step1A.size > 4 )
          if step1sub( @step1A, n, openCmd ) == true
            pushQ( :open, @step1A[n+1], outQ )
            @step1A.clear
            break
          end
        elsif @step1A[n].cmd == "RETR"
          if step1sub( @step1A, n, closeCmd ) == true
            @step1A[n].time = @step1A[n+1].time
            @step1A[n].timeS = @step1A[n+1].timeS
            pushQ( :close, @step1A[n], outQ )
            @step1A.clear
            break
          end
        end
        if @step1A[n+1] != nil and
          @step1A[n].cmd == "EPSV" and
          @step1A[n+1].cmd == :fin 
          delMark( @step1A, id, n , 2 )
        end
      end
      
      @step1A.delete_if do |tmp|
        if tmp.delMark[id] == true
          #Log::puts("extendeLog del #{tmp.base} #{tmp.timeS}",3)
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
