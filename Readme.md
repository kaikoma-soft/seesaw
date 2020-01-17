
## seesaw とは

本プログラムは,
Samba と連携して、Samba経由で再生した動画ファイルの
未視聴／視聴済 を記録し、playList を生成する
ソフトウェアです。

## 背景・目的

PC で録画した動画ファイルを、居間の TV に接続した Fire TV stick や、
タブレットの VLC 等の再生ソフトを使って視聴しているが、
ファイルが溜まってくると、見た／見ていないの管理が煩わしい。
（後でBDに保存するので、見たら消す方式は使えない。）
<br>
そこで、新規のファイルは「未視聴」に、動画再生すれば自動的に「視聴済」
に分類される仕組みを作成した。


## 動作概要

* 視聴する動画ファイルがあるディレクトリ(*1)を指定する。
* ディレクトリ(*1)検索し、DB に登録する。
  * 新規追加されたファイルは、「未視聴」に分類される。
  * 全てのファイルは、「全て」の含まれる
* 未視聴／視聴済／全て の３つ分類してシンボリックリンク(*2)を生成する。
* samba のアクセスログを監視し、条件を満たすと「未視聴」「視聴済」が入れ替わる。
* 条件とは、
  * 1分以上再生する。(config.rb で変更可) ただし猶予期間中に再度再生開始するとキャンセルされる。
  * 1分以内に、2秒以上の再生を2回繰り返す。


* 視聴する動画があるディレクトリのイメージ (*1)
```
    ├── 番組A
    │     ├── 番組A #01.mp4
    │     ├── 番組A #02.mp4
    │     └── 番組A #03.mp4
    └── 番組B
           ├── 番組B #01.mp4
           └── 番組B #02.mp4
```

* seesaw が生成するシンボリックリンク群のイメージ(*2)
```
    ├── 視聴済
    │     ├── 番組A
    │     │     └── 番組A #01.mp4
    │     └── 番組B
    │            └── 番組B #01.mp4
    ├── 全て
    │     ├── 番組A
    │     │     ├── 番組A #01.mp4
    │     │     ├── 番組A #02.mp4
    │     │     └── 番組A #03.mp4
    │     └── 番組B
    │            ├── 番組B #01.mp4
    │            └── 番組B #02.mp4
    └── 未視聴
           ├── 番組A
           │     ├── 番組A #02.mp4
           │     └── 番組A #03.mp4
           └── 番組B
                  └── 番組B #02.mp4
```

## 詳細
インストール方法等の詳細は、
[GitHub Pages](https://kaikoma-soft.github.io/seesaw.html)
を参照して下さい。



## 連絡先

不具合報告などは、
[GitHub issuse](https://github.com/kaikoma-soft/seesaw/issues)
の方にお願いします。


## ライセンス
このソフトウェアは、Apache License Version 2.0 ライセンスのも
とで公開します。詳しくは LICENSE を見て下さい。



