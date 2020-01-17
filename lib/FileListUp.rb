# coding: utf-8

require "find"
require 'fileutils'

class FileListUp

  attr_reader :findtime

  def initialize(  )
    @findtime = 0
    @ext = {}
    @@exclude = []

    setExclude()
  end

  def setExclude()
    @@exclude = []
    TargetExt.each {|e| @ext[ ".#{e}" ] = true }
    if Exclude.class == Array
      Exclude.each {|e| @@exclude << Regexp.new( e ) }
    elsif Exclude.class == String
      if FileTest.exist?( Exclude )
        File.open( Exclude, "r" ) do |fp|
          fp.each_line do |line|
            line = line.strip.chomp
            if line.size > 0
               @@exclude << Regexp.new( line )
            end
          end
        end
      end
    end
  end

  def exclude?( path )
    @@exclude.each do |pat|
      if pat =~ path
        Log::puts("exclude: #{path}", 6)
        return true
      end
    end
    false
  end
  
  def find(  )
    now = Time.now.to_i
    target = DBTarget.new
    DBaccess.new().open do |db|
      db.transaction do
        TargetDir.each do |base|
          topDir = File.basename( base )
          Find.find( base ) do |abspath|
            ext = File.extname( abspath )
            if @ext[ ext ] == true
              path = abspath.sub(/^#{base}\//,'')
              stat = NotYet
              stat = NA if exclude?( abspath ) == true

              # DB に登録
              ret = target.select( db, apath: abspath )
              if ret.size == 0
                Log::puts("add #{stat} #{path} ", 1)
                path = windowsForbid( path )
                topDir = windowsForbid( topDir )
                target.insert( db, path,abspath,topDir, stat, now )
              else
                if stat != ret[0][:stat] and (stat == NA or ret[0][:stat] == NA)
                  target.update( db, ret[0][:id], updatetime: now, stat: stat )
                else
                  target.update( db, ret[0][:id], updatetime: now )
                end
              end
            end
          end
        end

        # 更新されなかったものを削除する
        ret = target.select( db,  updatetime: now )
        ret.each do |r|
          Log::puts("del #{r[:rpath]}", 1)
          target.delete( db, r[:id] )
          [ makeLinkPath( r ), makeLinkPath( r, NA ) ].each do |path|
            if path != nil
              if FileTest.symlink?( path )
                Log::puts("del #{path}", 1)
                File.unlink( path )
              end
            end
          end
        end
      end
    end

    # link の作成
    createSymlinkAll()

    # 空になったディレクトリを削除
    delEmptyDir( )
    @findtime = Time.now
  end

  def delEmptyDir( dir = OutputDir )
    Dir.entries( dir ).sort.each do |dir1|
      if dir1 != '..' && dir1 != '.'
        path = dir + "/" + dir1
        if test( ?d, path )
          if Dir.entries( path ).size == 2
            Log::puts("rmdir #{path}" )
            Dir.rmdir( path )
          else
            delEmptyDir( path )
          end
        end
      end
    end
  end

  def delEmptyDirS( path )
    if test( ?d, path )
      if Dir.entries( path ).size == 2
        Log::puts("rmdir #{path}" )
        Dir.rmdir( path )
      end
    end
  end

  #
  #  windows の禁止文字を変換
  #
  def windowsForbid( str )
    char = { 
      #/\// => '／',
      /\:/ => '：',
      /\*/ => '＊',
      /\?/ => '？',
      /\"/ => '”',
      /\</ => '＜',
      /\>/ => '＞',
      /\|/ => '｜',
      /\\/ => '￥',
    }
    ret = str.dup
    char.each_pair do |k,v|
      ret.gsub!(k,v )
    end
    ret
  end
  
  def makeLinkPath( d, subdir = nil )
    ret = nil
    if subdir == nil
      subdir2 = StatStr[ d[:stat] ]
    else
      subdir2 = StatStr[  subdir ]
    end
    if subdir2 != nil
      ret = sprintf("%s/%s/%s/%s",OutputDir,d[:topdir],subdir2,d[:rpath])
      ret = windowsForbid( ret )
    end
    ret
  end
  
  
  def createSymlinkAll()

    target = DBTarget.new
    DBaccess.new().open do |db|
      target.select( db ).each do |d|
        if d[:stat] == NA
          [ NotYet, Done ].each do |n|
            path = makeLinkPath( d, n )
            if FileTest.symlink?( path )
              Log::puts("unlink #{path}")
              File.unlink( path )
            end
          end
        else
          createSymlink( d )
        end
        createSymlink( d, NA )
      end
    end
  end
  
  def createSymlink( d, subdir = nil)
    if ( path = makeLinkPath( d, subdir )) != nil
      dir = File.dirname( path )
      FileUtils.mkpath( dir )

      if FileTest.symlink?( path )
        link = File.readlink(path)
        if link != d[:apath]
          File.unlink( path )
          Log::puts("link 先変更")
        else
          return
        end
      end
      File.symlink( d[:apath], path )
    end
  end

  #
  #  未->既、既->未 反転
  #
  def flip( r )
    stat2 = r[:stat] == NotYet ? Done : NotYet

    # 古い linkを削除
    if (path = makeLinkPath( r, r[:stat] )) != nil
      if FileTest.symlink?( path )
        File.unlink( path )
        delEmptyDirS( File.dirname( path ) )
      end
    end

    # 新しい linkを作成
    if ( path = makeLinkPath( r, stat2 )) != nil
      dir = File.dirname( path )
      FileUtils.mkpath( dir )
      File.unlink( path ) if FileTest.symlink?( path )
      File.symlink( r[:apath], path )
    end
  end
  
end
