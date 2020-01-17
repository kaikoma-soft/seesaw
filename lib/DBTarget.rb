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
    }
    @para = []
    @list.each_pair { |k,v| @para << v }
    
  end

  #
  #   格納
  #
  def insert(db, rpath,apath,topdir,stat, updatetime )
    sql = "insert into #{@tbl_name} ( rpath,apath,topdir,stat, updatetime) values (?,?,?,?,?);";
    db.execute( sql, rpath,apath,topdir,stat, updatetime )
  end


  #
  #   検索
  #
  def select( db, apath: nil, rpath: nil, stat: nil, updatetime: nil )
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
    if updatetime != nil
      where << " updatetime < ? "
      argv  << updatetime
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
