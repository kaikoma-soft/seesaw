# coding: utf-8

PNAME     = "seesaw"
Version   = "0.1.1"

LockFN    = BaseDir + "/#{PNAME}.lock"
PidFile   = BaseDir + "/#{PNAME}.pid"
DbFname   = BaseDir + "/#{PNAME}.db"
LogFname  = BaseDir + "/#{PNAME}.log"
OutputDir = BaseDir + "/playlist"


NotYet = 0
Done   = 1
NA     = 2
StatStr       = { NotYet => "未視聴",   Done => "視聴済",  NA => "全て" }

