# coding: utf-8

require 'optparse'

class Arguments

  attr_reader :background       # バックグランドで実行
  attr_reader :debug            # debug
  attr_reader :notyet           # 正規表現に一致するものを未視聴に
  attr_reader :done             # 正規表現に一致するものを視聴済に
  attr_reader :test             # notyet/done で、表示のみ
  attr_reader :logLevel         # ログ出力のレベル
  attr_reader :kill             # バックグランドで実行しているものを殺す。
  attr_reader :refresh          # ディレクトリの再検索
  attr_reader :web              # web の起動
  attr_reader :httpPort         # http port 番号

  def initialize(argv)
    @background = false
    @debug = false
    @inv = nil
    @test = false
    @logLevel = 1
    @notyet = nil
    @done   = nil
    @kill   = false
    @refresh = false
    @web    = false
    @httpPort = 8888
    
    op = option_parser
    op.parse!(argv)
  rescue OptionParser::ParseError => e
    $stderr.puts e
    exit(1)
  end

  private

  def option_parser
    OptionParser.new do |op|
      op.on('-b', '--background','exec background') { |t| @background = !@background }
      op.on('--done str',   '視聴済に')             { |t| @done = t }
      op.on('--notyet str', '未視聴に')             { |t| @notyet = t }
      op.on('-t', 'test mode for notyet/done')      { |t| @test = !@test }
      op.on('-k','--kill', 'kill background proc')  { |t| @kill = true }
      op.on('-d', '--debug', 'debug mode')          { |t| @debug = !@debug }
      op.on('-l n','--loglevel','set log level')    { |t| @logLevel = t.to_i }
      op.on('-r', '--reload','data refresh')        { |t| @refresh = true }
      op.on('-w', '--web','web interface')          { |t| @web = true }
      op.on('-p n', '--port n','web port')          { |t| @httpPort = t.to_i }
    end
  end

end
