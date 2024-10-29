#!/usr/bin/ruby
# -*- coding: utf-8 -*-


class DBTarget

  def initialize( )
    @tbl_name = "target"
    @list = {
      id:        "id",
      rpath:     "rpath",
      apath:     "apath",
      topdir:     "topdir",
      stat:       "stat",
      updatetime: "updatetime",
      idpath:     "idpath",
    }
    @para = []
    @list.each_pair { |k,v| @para << v }
    
  end

  #
  #  テーブルに項目追加 ( 追加した場合 true )
  #
  def addidPath( db )
    sql = "select * from sqlite_master where type='table' and name='target' ;"
    r = db.execute( sql)
    r.first.each do |tmp|
      if tmp.class == String
        return false if tmp =~ /idpath/
      end
    end
    sql = "ALTER TABLE target ADD COLUMN idpath text;"
    Log::puts( sql, 0)
    db.execute( sql)
    sql = "create index data2 on target (idpath);"
    db.execute( sql)
    return true
  end
  

  #
  #  idpath の作成
  #
  def makeidPath( db )
    sql = "select #{@para.join(",")} from #{@tbl_name} "
    row = db.execute( sql )
    r = db.row2hash( @list, row )
    flu = FileListUp.new
    sql = "update #{@tbl_name} set idpath = ? where id = ? ;";
    r.each do |tmp|
      if tmp[:idpath ] == nil
        idpath = flu.windowsForbid( File.join( tmp[:topdir],tmp[:rpath] ) )
        idpath = idpath.gsub(/ /,"_").gsub(/_+/,"_")
        db.execute( sql, idpath, tmp[:id] )
      end
    end

  end
  
  #
  #   格納
  #
  def insert(db, rpath,apath,topdir,stat, updatetime )
    sql = "insert into #{@tbl_name} ( rpath,apath,topdir,stat, updatetime,idpath) values (?,?,?,?,?,?);";
    if rpath != nil and topdir != nil
      idPath = FileListUp.new.windowsForbid( File.join( topdir,rpath) )
      idPath = idPath.gsub(/ /,"_").gsub(/_+/,"_")
      db.execute( sql, rpath,apath,topdir,stat, updatetime, idPath )
    else
      Log::puts( "Error: rpath or topdir is nil #{apath}", 0)
      return
    end
    
  end


  #
  #   検索
  #
  def select( db, apath: nil, rpath: nil, topdir: nil, stat: nil, updatetime: nil, idpath: nil )
    sql = "select #{@para.join(",")} from #{@tbl_name} "
    where = []
    argv = []
    if apath != nil
      where << " apath = ? "
      argv  << apath
    end
    if rpath != nil
      where << " rpath = ? "
      argv  << rpath
    end
    if stat != nil
      where << " stat = ? "
      argv  << stat
    end
    if topdir != nil
      where << " topdir = ? "
      argv  << topdir
    end
    if updatetime != nil
      where << " updatetime < ? "
      argv  << updatetime
    end
    if idpath != nil
      where << " idpath = ? "
      argv  << idpath
    end

    if where.size > 0
      sql += " where " + where.join(" and ")
    end
    row = db.execute( sql, *argv )
    db.row2hash( @list, row )
  end


  #
  #   更新
  #
  def update( db, id, stat: nil, updatetime: nil  )
    sql = "update #{@tbl_name} set "
    set = []
    argv = []
    if stat != nil
      set   << " stat = ? "
      argv  << stat
    end
    if updatetime != nil
      set  << " updatetime = ? "
      argv << updatetime
    end

    if set.size > 0
      sql += set.join(",")
    end
    sql += " where id = ? "
    argv << id

    row = db.execute( sql, *argv )
  end


  #
  #  削除
  #
  def delete( db, id )
    sql = "delete from #{@tbl_name} where id = ? ;"
    db.execute( sql, id )
  end

  
end
