#!/usr/bin/ruby
# -*- coding: utf-8 -*-


class DBaccess

  #
  #  SQLite の初期化
  #
  def createDB()

    sql = <<EOS
--
-- チャンネル情報
--
create table target (
    id                  integer  primary key,
    rpath               text,     -- 相対パス
    apath               text,     -- 絶対パス
    topdir              text,     -- TOP dir
    stat                integer,  -- 状態 0:未  1:既  2:除外
    updatetime          integer,  -- 更新日時
    idpath              text      -- 検索のための 加工された key
);
create index data1 on target (rpath) ;
create index data2 on target (idpath) ;


--
--  変数保存
--
create table keyval (
    key               text primary key,     -- キー
    val               integer               -- 値 
); --   
create index keyval1 on keyval (key) ;


EOS
    
    @db.execute_batch(sql)

  end



end
