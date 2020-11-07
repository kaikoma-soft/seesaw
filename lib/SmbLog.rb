# coding: utf-8
#


#
#  samba アクセスlog解析
#
require 'rubygems'
require 'optparse'
require 'sqlite3'

class SmbLog

  attr_reader  :acctime
  
  def initialize( )
    @logfname = SambaLog
    @basedir  = OutputDir
    @fp       = nil
    @fsize    = 0
    @lastTime = 0
    @openqueue  = []             # step1 open キュー
    @closequeue = []             # step2 close済みキュー
    if ( ts = timeStamp(:get)) != 0 
      @timeStamp = ts
    else
      @timeStamp = Time.now.to_i
    end

    str = StatStr.values.join("|")
    ext = TargetExt.join("|")
    @pathReg = /\/([^\/]*\/(#{str})\/.*?\.(#{ext}))$/
    @acctime = Time.now

    open()
  end

  def timeStamp( flag = :get, val = nil )
    kv = DBkeyval.new
    key = "timeStamp"
    DBaccess.new().open do |db|
      if flag == :get 
        if ( ret = kv.select( db, key )) == nil
          return 0
        else
          return ret
        end
      elsif flag == :set
        kv.upsert( db, key, val )
      end
    end
  end
  
  class QueueData1
    attr_reader :fname, :time, :type
    attr_accessor :delMark
    def initialize( time,type,fname )
      @fname = fname
      @time = time
      @type = case type
              when "open" then :open
              when "close" then :close
              end
      @delMark = false
    end
  end

  class QueueData2
    attr_reader :fname, :start, :fin, :len, :type
    attr_accessor :delMark
    
    def initialize( start, fin, fname )
      @fname = fname
      @start = start
      @fin   = fin
      @len   = fin - start
      @type  = @len > DoneTime ? :long : :short
      @delMark = false
    end
  end
  
  def open()
    if test( ?f, @logfname )
      if ( @fp = File.open( @logfname, "r") ) == nil
        raise "samba access log file can't open (#{@logfname})\n"
      end
    else
      raise "samba access log file not found (#{@logfname})\n"
    end

    @fsize = File.size( @logfname )
  end

  def close()
    if @fp != nil
      @fp.close
    end
    @fsize = 0
  end

  def reopen()
    Log::puts("reopen #{@logfname}",3)
    close()
    open()
  end

  
  def readLog()
    timeStamp = @timeStamp
    while ( line = @fp.gets()) != nil
      if line =~ /smbd_audit:\s+(\d+)\/(\d+)\/(\d+)\s(\d+):(\d+):(\d+)\|(\w+)\|(open|close)\|(.*)/
        (y,m,d,h,m2,s ) = [ $1,$2,$3,$4,$5,$6 ]
        user = $7
        type = $8
        tmp = $9
        if type == "open"
          if tmp =~ /^ok\|r\|(.*)/
            fname = $1
          end
        else
          if tmp =~ /^ok\|(.*)/
            fname = $1
          end
        end
        time = Time.local( y,m,d,h,m2,s )
        if time.to_i > @timeStamp
          timeStamp = time.to_i
          if fname =~ @pathReg
            fname2 = $1
            path = (@basedir + "/" + fname2).gsub(/\/\//,'/')
            if FileTest.symlink?( path )
              if type == "open"
                @openqueue << QueueData1.new( time,type,fname2 )
                Log::puts("open #{fname2} #{time}",3)
              elsif type == "close"
                Log::puts("close #{fname2} #{time}",3)
                openClose( fname2, time )
              end
            else
              Log::puts("not found #{path}",5)
            end
          end
          @acctime = Time.now
        end
      end
    end
    if timeStamp > @timeStamp
      timeStamp( :set, timeStamp )
    end
  end


  #
  # open-close の対の検出
  #
  def openClose( fname, time )
    now = Time.now
    @openqueue.each_with_index do |tmp,n|
      if tmp.fname == fname
        len = time - tmp.time
        if len > 1              # 2秒以上を登録
          Log::puts("openClose add closeQ #{fname} #{tmp.time} - #{time} = #{len}",3)
          @closequeue << QueueData2.new( tmp.time, time, fname )
          tmp.delMark = true
        else                    # 2秒以下はノイズとして無視
          Log::puts("openClose ignore #{fname} #{len}",3)
          tmp.delMark = true
        end
        break
      end
      if ( now - tmp.time ) > 3600 * 3 # 古くなったものは捨てる
        Log::puts("openClose old #{tmp.fname}",3)
        tmp.delMark = true
      end
    end

    @openqueue.delete_if do |tmp|
      if tmp.delMark == true
        Log::puts("openClose del #{tmp.fname} #{tmp.time}",3)
        true
      end
    end
    
  end

  #
  #  ファイルがopen中かチェック
  #
  def openChk?( fname )
    @openqueue.each do |tmp|
      if tmp.fname == fname
        return true
      end
    end
    false
  end

  #
  #  short アクセスがあるか check
  #
  def shortChk?( prev )
    @closequeue.each do |tmp|
      if tmp.fname == prev.fname and tmp.type == :short
        if tmp.start > prev.start
          tmp.delMark = true
          return true
        end
      end
    end
    false
  end

  
  #
  #  close済み queue から取り出し
  #
  def fetchCQ()         # fetchCloseQueue
    ret = []
    prev = nil
    now = Time.now
    @closequeue.each_with_index do |tmp,n|
      if tmp.len > DoneTime and ( now - tmp.fin ) > FlipDelay
        if shortChk?( tmp ) == true
          Log::puts("fetchCQ shortChk?() true #{tmp.fname}",3)
          tmp.delMark = true
        elsif openChk?( tmp.fname ) == true
          Log::puts("fetchCQ openChk?() true #{tmp.fname}",3)
          tmp.delMark = true
        else
          tmp.delMark = true
          ret << tmp.fname
          Log::puts("fetchCQ ok #{tmp.fname}",3)
          next
        end
      end
      if prev != nil
        if prev.type == :short and tmp.type == :short
          if tmp.fname == prev.fname
            if ( tmp.fin - prev.fin ).abs < DoneTime
              tmp.delMark = true
              prev.delMark = true
              ret << tmp.fname
              Log::puts("fetchCQ double add #{tmp.fname} #{tmp.start}",3)
            end
          end
        end
      end
      if ( now - tmp.fin ) > ( FlipDelay * 5 ) # 古くなったものは捨てる
        tmp.delMark = true
      end
      prev = tmp
    end

    @closequeue.delete_if do |tmp|
      if tmp.delMark == true
        Log::puts("fetchCQ del #{tmp.fname} #{tmp.start}",3)
        true
      end
    end
    
    ret.uniq
  end
    
  def reset?()
    true if @fsize > File.size( @logfname )
    false
  end
end

if $0 == __FILE__
  base = File.dirname( $0 )
  $: << base
  require 'require.rb'

  sm = SmbLog.new()

  sm.watch()
  sleep(60)

end
