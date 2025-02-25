#!/usr/bin/ruby
# -*- coding: utf-8 -*-


class DBkeyval

  def initialize( )
    @tbl_name = "keyval"
  end

  #
  #   格納
  #
  def insert(db, key, val )
    sql = "insert into #{@tbl_name} ( key, val ) values (?,?);";
    db.execute( sql, key, val )
  end


  #
  #   検索
  #
  def select( db, key )
    sql = "select val from #{@tbl_name} where key = ? ;"
    row = db.execute( sql, key)
    if row != nil and row[0] != nil
      return  row[0][0]
    end
    nil
  end


  #
  #  削除
  #
  def delete( db, key )
    sql = "delete from #{@tbl_name} where key = ? ;"
    db.execute( sql, key )
  end

  #
  #  更新
  #
  def upsert( db, key, val )
    sql = "INSERT OR REPLACE INTO #{@tbl_name} (key, val) VALUES (?,?) ;"
    db.execute( sql, key, val )
  end

  #
  #  タイムスタンプの保存/取得
  #
  def timeStamp( flag = :get, val = nil )
    kv = self #DBkeyval.new
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
  
  
end
