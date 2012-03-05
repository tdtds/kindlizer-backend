# Kindle-Backend
ニュースサイトを定期的にスクレイピングしてmobiファイルを生成し、Kindle Personal Documentへメールで送信するサービス

ニュースの電子書籍化と配信を自動化するソフトウェアとしては電子書籍管理ツールであるCalibreが豊富なレシピで抜きん出た存在ですが、クライアントPCを常時稼動しておかなくてはならず、環境面で稼働が難しい面があります(電力消費に厳しい2012年の日本では特に)。そこで、クラウド上で稼働する同様の仕組みを作りました。ただしレシピはまだぜんぜんありません(作者が使っている日経新聞電子版とINTERNET Watchのみ)。

## 仕組み
Heroku上で稼働することを前提に作られたサーバアプリケーションです。Clockworkを使って1時間ごとにタスクが起きるようになっています(毎時04分)。

実際にどのサイトをmobiファイル化するのかというタイミングは、環境変数'KINDLIZER_CONFIG'を使って外部から与えます。指定したURIにはyamlファイルを設置しておきます。なお、このyamlファイルは毎時起動するタイミングで読み込まれるので、ファイルを書き換えるだけで次回の実行時に変更が反映されます。

yamlファイルで指定された時刻になると、そこに指示されたサイトのスクレイピングが走ります。例えば朝4時にはサイトhogeとfoo、夕方18時にはhogeのみという指定はこのようになるでしょう:

```yaml
:task:
  4:
  - hoge
  - foo
  18:
  - hoge
```

mobiファイルの生成に成功すると、指定したアドレスにメールで送ります。実際は〜@free.kindle.comになるでしょう(:to)。また、送信元のアドレスもKindle Personal Documentで許可したアドレスを指定して置く必要があります(:from)。

また、稼動しているサーバのTimezoneに依存しないようにするため、設定ファイルではTimezoneも指定します(:tz)。これらの指定方法はconfig.yamlを参考にしてください。

## 動かし方
主にHerokuで動かすことを想定していますので、Herokuのアカウントを取得済みで、各種アドオンを使えるようにするためのクレジットカード認証は済んでいることとします。ただしすべて無料の範囲内で利用できます。

まずはコードの入手:

```sh
% git clone https://tdtds@github.com/tdtds/kindlizer-backend.git
% cd kindlizer-backend
```

config.yamlというファイルがあるので、適当な名前でコピーして、内容を書き換えます。そしてそのファイルをインターネット上で見える場所に設置し、そのURIを取得しておいて下さい(Dropboxにでも入れて、共有リンクを使うのも手です)。

続いてHeroku上に環境構築:

```sh
% gem install heroku
% heroku apps:create --stack cedar
% heroku addons:add sendgrid:starter
% heroku config:add KINDLIZER_CONFIG=[YOUR YAML URI] RACK_ENV=production
% git push heroku
% git ps:scale web=0 clock=1
```

これで動くはず。ログをみて、動作状況を確認しましょう::

```sh
% heroku logs -t
```

## ジェネレータの作り方
あとで書く。
