#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'sqlite3'

class DBaccess

  attr_reader :db
  
  def initialize( dbFname = DbFname )
    @db = nil
    @DBfile = dbFname
    @DBLockfile = dbFname + ".flock"
    unless File.exist?(@DBfile )
      open() do |db|
        db.transaction do
          pp "createDB()"
          createDB()
          pp "createDB() end"
        end
      end
      File.chmod( 0600, @DBfile )
    end
  end

  def open
    File.open(@DBLockfile, File::RDWR|File::CREAT, 0644) do |fl|
      fl.flock(File::LOCK_EX)
      @db = SQLite3::Database.new( @DBfile )
      @db.busy_timeout(1000)
      ecount = 0
      begin
        yield self
      rescue SQLite3::BusyException
        STDERR.print ">SQLite3::BusyException #{ecount}\n"
        STDERR.flush()
        if ecount > 10
          STDERR.print ">SQLite3::BusyException exit\n"
          raise
        end
        ecount += 1
        sleep( rand(1.0..3.0) )
        retry
      rescue => e
        p $!
        puts e.backtrace.first + ": #{e.message} (#{e.class})"
        e.backtrace[1..-1].each { |m| puts "\tfrom #{m}" }
        ecount += 1
        if ecount > 10
          STDERR.print ">SQLite3::BusyException exit\n"
          raise
        end
        sleep( rand(1.0..3.0) )
        retry
      end
      close()
    end
  end
  
  def close
    if @db != nil
      @db.close()
      @db = nil
    end
  end

  def execute( *args )
    @db.execute( *args )
  end

  def transaction()
    @db.transaction do
      yield
    end
  end

  def prepare( str )
    @db.prepare( str )
  end
  
  def row2hash( list, row )
    r = []
    if row != nil
      row.each do |tmp|
        h = {}
        list.each_key { |k| h[k] = tmp.shift }
        r << h
      end
    end
    r
  end

    
end
