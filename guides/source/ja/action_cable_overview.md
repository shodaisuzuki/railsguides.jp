Action Cable の概要
=====================

本ガイドでは、Action Cableのしくみと、WebSocketをRailsアプリケーションに導入してリアルタイム機能を実現する方法について解説します。

このガイドの内容:

* Action Cableの概要、バックエンドとフロントエンドの統合
* Action Cableの設定方法
* チャネルの設定方法
* Action Cable向けのデプロイとアーキテクチャの設定

--------------------------------------------------------------------------------


はじめに
------------

Action Cableは、
[WebSocket](https://ja.wikipedia.org/wiki/WebSocket)とRailsのその他の部分をシームレスに統合するためのものです。Action Cable が導入されたことで、Rails アプリケーションの効率の良さとスケーラビリティを損なわずに、通常のRailsアプリケーションと同じスタイル・方法でリアルタイム機能をRubyで記述できます。クライアント側のJavaScriptフレームワークとサーバー側のRubyフレームワークを同時に提供する、フルスタックのフレームワークです。Active RecordなどのORMで書かれたすべてのドメインモデルにアクセスできます。

用語について
-----------

1個のAction Cableサーバーは、コネクションインスタンスを複数扱え、WebSocketのコネクションごとに1つのコネクションインスタンスを持ちます。1人のユーザーは、ブラウザタブを複数開いたり複数のデバイスを用いている場合、アプリケーションに対して複数のWebSocketコネクションをオープンします。WebSocketコネクションのクライアントは「コンシューマー（consumer）」と呼ばれます。

各コンシューマーは、複数のケーブルチャネルにサブスクライブできます。各チャネルには機能の論理的な単位がカプセル化され、そこで行われることは、コントローラが通常のMVPセットアップで行うことと似ています。たとえば`ChatChannel`と`AppearancesChannel`が1つずつあり、あるコンシューマーがそれらチャネルの一方または両方にサブスクライブされることができます。1つのコンシューマーは、少なくとも1つのチャネルにサブスクライブされるべきです。

コンシューマーがあるチャネルにサブスクライブされると「サブスクライバ（subscriber）」として振る舞います。サブスクライバとチャネルの間のコネクションは、（驚いたことに）サブスクリプションと呼ばれます。あるコンシューマーは、何度でも指定のチャンネルのサブスクライバとして振る舞えます。たとえば、あるコンシューマーが複数のチャットルームに同時にサブスクライブしてもよいのです（物理的なユーザーは複数のコンシューマーを持つことができ、1つのタブやデバイスごとに接続をオープンできることをお忘れなく）。

各チャネルは、その後何もストリーミングしないことも、さらにブロードキャストすることもできます。ブロードキャストとは、ブロードキャスター（broadcaster）によって転送されるあらゆるものがチャネルのサブスクライバ（サブスクライバはその名前が付いたブロードキャストをストリーミングします）に直接送信されるpubsubリンクです。

以上のように、アーキテクチャ上のスタックとしてはある程度深くなっています。新しいものを表す用語も多数あり、何よりも、機能単位ごとにクライアント側とサーバー側の両方についてリフレクションを扱うことになります。

Pub/Subについて
---------------

[Pub/Sub](https://ja.wikipedia.org/wiki/%E5%87%BA%E7%89%88-%E8%B3%BC%E8%AA%AD%E5%9E%8B%E3%83%A2%E3%83%87%E3%83%AB)はパブリッシャ-サブスクライバ（pub/sub）型モデルとも呼ばれる、メッセージキューのパラダイムです。パブリッシャ側（Publisher）が、サブスクライバ側（Subscriber）の抽象クラスに情報を送信します。
このとき、個別の受信者を指定しません。Action Cableは、サーバーと多数のクライアント間の通信にこのアプローチを採用しています。

## サーバー側のコンポーネント

### コネクション

**コネクション （Connection）** は、クライアントとサーバー間の関係を成立させる基礎となります。サーバーでWebSocketを受け付けるたびに、コネクションのオブジェクトがインスタンス化します。このオブジェクトは、今後作成されるすべての**チャネルサブスクライバ**の親となります。このコネクション自体は、認証や承認の後、特定のアプリケーションロジックを扱いません。WebSocketコネクションのクライアントは**コンシューマー**と呼ばれます。各ユーザーが開くブラウザタブ、ウィンドウ、デバイスごとに、コンシューマーのコネクションのペアが1つずつ作成されます。

コネクションは、`ApplicationCable::Connection`のインスタンスです。このクラスでは、受信したコネクションを承認し、ユーザーを特定できた場合にコネクションを確立します。

#### コネクションの設定

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private
      def find_verified_user
        if verified_user = User.find_by(id: cookies.encrypted[:user_id])
          verified_user
        else
          reject_unauthorized_connection
        end
      end
  end
end
```

上の`identified_by`はコネクションIDであり、後で特定のコネクションを見つけるときに利用できます。IDとしてマークされたものは、そのコネクション以外で作成されるすべてのチャネルインスタンスに、同じ名前で自動的にデリゲートを作成します。

この例では、アプリケーションの他の場所で既にユーザー認証を扱っており、認証成功によってユーザーIDに署名済みcookieが設定されていることを前提としています。

次に、新しいコネクションを求められたときにこのcookieがコネクションのインスタンスに自動で送信され、`current_user`の設定に使われます。現在の同じユーザーによるコネクションが識別されると、そのユーザーが開いているすべてのコネクションを取得することも、ユーザーが削除されたり認証できない場合に切断することもできるようになります。

### チャネル

**チャネル （Channel）** は、論理的な作業単位をカプセル化します。通常のMVC設定でコントローラが果たす役割と似ています。Railsはデフォルトで、チャネル間で共有されるロジックをカプセル化する`ApplicationCable::Channel`という親クラスを作成します。

#### 親チャネルの設定

```ruby
# app/channels/application_cable/channel.rb
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
```

上のコードによって、専用のChannelクラスを作成します。たとえば、
`ChatChannel`や`AppearanceChannel`などは次のように作成します。

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
end

# app/channels/appearance_channel.rb
class AppearanceChannel < ApplicationCable::Channel
end
```

これで、コンシューマーはこうしたチャネルをサブスクライブできるようになります。

#### サブスクリプション

コンシューマーは、チャネルを購読する**サブスクライバ**側（Subscriber）の役割を果たします。そして、コンシューマーのコネクションは**サブスクリプション*（Subscription: 購読）と呼ばれます。生成されたメッセージは、Action Cableコンシューマーが送信するIDに基いて、これらのチャネルサブスクライバ側にルーティングされます。

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  # コンシューマーがこのチャネルのサブスクライバ側になると
  # このコードが呼び出される
  def subscribed
  end
end
```

## クライアント側のコンポーネント

### コネクション

コンシューマー側でも、コネクションのインスタンスが必要になります。このコネクションは、Railsがデフォルトで生成する次のJavaScriptコードによって確立します。

#### コンシューマーの接続

```js
// app/javascript/channels/consumer.js
// Action Cable provides the framework to deal with WebSockets in Rails.
// You can generate new channels where WebSocket features live using the `rails generate channel` command.

import { createConsumer } from "@rails/actioncable"

export default createConsumer()
```


これにより、サーバーの`/cable`にデフォルトで接続するコンシューマーが準備されます。利用したいサブスクリプションを1つ以上指定しなければコネクションは確立しません。

このコンシューマーは、オプションとして接続先URLを指定する引数を1つ取れます。これは文字列でも、WebSocketがオープンされるときに呼び出されて文字列を返す関数でも構いません。

```js
// 異なる接続先URLを指定する
createConsumer('https://ws.example.com/cable')
// 動的にURLを生成する関数
createConsumer(getWebSocketURL)
function getWebSocketURL {
  const token = localStorage.get('auth-token')
  return `https://ws.example.com/cable?token=${token}`
}
```

#### サブスクライバ側

指定のチャネルにサブスクリプションを作成することで、コンシューマーがサブスクライバ側になります。

```js
// app/javascript/channels/chat_channel.js
import consumer from "./consumer"

consumer.subscriptions.create({ channel: "ChatChannel", room: "Best Room" })

// app/javascript/channels/appearance_channel.js
import consumer from "./consumer"
consumer.subscriptions.create({ channel: "AppearanceChannel" })
```

サブスクリプションは上のコードで作成されます。受信したデータに応答する機能については後述します。

コンシューマーは、指定のチャネルに対するサブスクライバ側として振る舞えます。回数の制限はありません。たとえば、コンシューマーはチャットルームを同時にいくつでもサブスクライブできます。

```js
// app/javascript/channels/chat_channel.js
import consumer from "./consumer"
consumer.subscriptions.create({ channel: "ChatChannel", room: "1st Room" })
consumer.subscriptions.create({ channel: "ChatChannel", room: "2nd Room" })
```

## クライアント-サーバー間のやりとり

### ストリーム

**ストリーム**（stream）は、ブロードキャストでパブリッシュするコンテンツをサブスクライバ側にルーティングする機能をチャネルに提供します。

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end
end
```

あるモデルに関連するストリームを作成すると、利用するブロードキャストがそのモデルとチャネルから生成されます。次の例 では、`comments:Z2lkOi8vVGVzdEFwcC9Qb3N0LzE`のような形式のブロードキャストでサブスクライブします。

```ruby
class CommentsChannel < ApplicationCable::Channel
  def subscribed
    post = Post.find(params[:id])
    stream_for post
  end 
end
```

これで、このチャネルに次のようにブロードキャストできるようになります。

```ruby
CommentsChannel.broadcast_to(@post, @comment)
```

### ブロードキャスト

**ブロードキャスト**（broadcasting）は、pub/subのリンクです。パブリッシャ側からの送信内容はすべてブロードキャストを経由し、その名前のブロードキャストをストリーミングするチャネルサブスクライバ側に直接ルーティングされます。各チャネルは、0個以上のブロードキャストをストリーミングできます。

ブロードキャストは純粋なオンラインキューであり、時間に依存します。ストリーミング（指定のチャネルへのサブスクライバ）を行っていないコンシューマーは、後で接続するときにブロードキャストを取得できません。

ブロードキャストは、Railsアプリケーションの別の場所で呼び出されます。

```ruby
WebNotificationsChannel.broadcast_to(
  current_user,
  title: 'New things!',
  body: 'All the news fit to print'
)
```

`WebNotificationsChannel.broadcast_to`呼び出しでは、メッセージを現在のサブスクリプションアダプタのpubsubキュー（このキューはユーザーごとに異なるブロードキャスト名の下にあります）。Action Cableのデフォルトのpubsubキューは、production環境では`redis`、development環境とtest環境では`async`になります。IDが1のユーザーなら、ブロードキャスト名は`web_notifications:1`のようになります。

このチャネルは、`web_notifications:1`に着信するものすべてを`received`コールバック呼び出しによってクライアントに直接ストリーミングするようになります。

### サブスクリプション

チャネルをサブスクライブしたコンシューマーは、サブスクライバ側として振る舞います。この接続もサブスクリプション (Subscription: サブスクライバ) と呼ばれます。着信メッセージは、Action Cableコンシューマーが送信するIDに基いて、これらのチャネルサブスクライバ側にルーティングされます。

```js
// app/javascript/channels/chat_channel.js
// Web通知を送信する権限が既にあることが前提
import consumer from "./consumer"
consumer.subscriptions.create({ channel: "ChatChannel", room: "Best Room" }, {
  received(data) {
    this.appendLine(data)
  },
  appendLine(data) {
    const html = this.createLine(data)
    const element = document.querySelector("[data-chat-room='Best Room']")
    element.insertAdjacentHTML("beforeend", html)
  },
  createLine(data) {
    return `
      <article class="chat-line">
        <span class="speaker">${data["sent_by"]}</span>
        <span class="body">${data["body"]}</span>
      </article>
    `
  }
})
```

### チャネルにパラメータを渡す

サブスクリプション作成時に、クライアント側のパラメータをサーバー側に渡すことができます。以下に例を示します。

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end
end
```

`subscriptions.create`に最初の引数として渡されるオブジェクトは、Action Cableチャネルのparamsハッシュになります。キーワード`channel`の指定は省略できません。

```js
// app/javascript/channels/chat_channel.js
import consumer from "./consumer"
consumer.subscriptions.create({ channel: "ChatChannel", room: "Best Room" }, {
  received(data) {
    this.appendLine(data)
  },
  appendLine(data) {
    const html = this.createLine(data)
    const element = document.querySelector("[data-chat-room='Best Room']")
    element.insertAdjacentHTML("beforeend", html)
  },
  createLine(data) {
    return `
      <article class="chat-line">
        <span class="speaker">${data["sent_by"]}</span>
        <span class="body">${data["body"]}</span>
      </article>
    `
  }
})
```

```ruby
# このコードはアプリケーションのどこかで呼び出される
# おそらくNewCommentJobなどのあたりで
ActionCable.server.broadcast(
  "chat_#{room}",
  sent_by: 'Paul',
  body: 'This is a cool chat app. '
)
```

### メッセージを再ブロードキャストする

あるクライアントから、接続している別のクライアントに、メッセージを*再ブロードキャスト*することはよくあります。

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end

  def receive(data)
    ActionCable.server.broadcast("chat_#{params[:room]}", data)
  end
end
```

```js
// app/javascript/channels/chat_channel.js
import consumer from "./consumer"
const chatChannel = consumer.subscriptions.create({ channel: "ChatChannel", room: "Best Room" }, {
  received(data) {
    // data => { sent_by: "Paul", body: "This is a cool chat app." }
  }
}

chatChannel.send({ sent_by: "Paul", body: "This is a cool chat app." })
```

再ブロードキャストは、接続しているすべてのクライアントで受信されます。送信元クライアント自身も再ブロードキャストを受信します。利用するparamsは、チャネルをサブスクライブするときと同じです。

## フルスタックの例

以下の設定手順は、2つの例で共通です。

  1. [コネクションを設定](#コンシューマーの設定)
  2. [親チャネルを設定](#親チャネルの設定
  3. [コンシューマーを接続](#コンシューマーの接続)

### 例1: ユーザーアピアランスの表示

これは、ユーザーがオンラインかどうか、ユーザーがどのページを開いているかという情報を追跡するチャネルの簡単な例です（オンラインユーザーの横に緑の点を表示する機能を作成する場合などに便利です）。

サーバー側のアピアランスチャネルを作成します。

```ruby
# app/channels/appearance_channel.rb
class AppearanceChannel < ApplicationCable::Channel
  def subscribed
    current_user.appear
  end

  def unsubscribed
    current_user.disappear
  end

  def appear(data)
    current_user.appear(on: data['appearing_on'])
  end

  def away
    current_user.away
  end
end
```

サブスクリプションが開始されると、`subscribed`コールバックがトリガーされ、そのユーザーがオンラインであることが示されます。このアピアランスAPIをRedisやデータベースなどと連携することもできます。

クライアント側のアピアランスチャネルを作成します。

```js
// app/javascript/channels/appearance_channel.js
import consumer from "./consumer"
consumer.subscriptions.create("AppearanceChannel", {
  // サブスクリプションが作成されると1度呼び出される
  initialized() {
    this.update = this.update.bind(this)
  },
  // サブスクリプションがサーバーで利用可能になると呼び出される
  connected() {
    this.install()
    this.update()
  },
  // WebSocketコネクションがクローズすると呼び出される
  disconnected() {
    this.uninstall()
  },
  // サブスクリプションがサーバーで却下されると呼び出される
  rejected() {
    this.uninstall()
  },
  update() {
    this.documentIsActive ? this.appear() : this.away()
  },
  appear() {
    // サーバーの`AppearanceChannel#appear(data)`を呼び出す
    this.perform("appear", { appearing_on: this.appearingOn })
  },
  away() {
    // サーバーの`AppearanceChannel#away`を呼び出す
    this.perform("away")
  },
  install() {
    window.addEventListener("focus", this.update)
    window.addEventListener("blur", this.update)
    document.addEventListener("turbolinks:load", this.update)
    document.addEventListener("visibilitychange", this.update)
  },
  uninstall() {
    window.removeEventListener("focus", this.update)
    window.removeEventListener("blur", this.update)
    document.removeEventListener("turbolinks:load", this.update)
    document.removeEventListener("visibilitychange", this.update)
  },
  get documentIsActive() {
    return document.visibilityState == "visible" && document.hasFocus()
  },
  get appearingOn() {
    const element = document.querySelector("[data-appearing-on]")
    return element ? element.getAttribute("data-appearing-on") : null
  }
})
```

##### クライアント-サーバー間のやりとり

1. **クライアント**は**サーバー**に`App.cable = ActionCable.createConsumer("ws://cable.example.com")`経由で接続する（`cable.js`）。**サーバー**は、このコネクションの認識に`current_user`を使う。

2. **クライアント**はアピアランスチャネルに`consumer.subscriptions.create({ channel: "AppearanceChannel" })`経由で接続する（`appearance_channel.js`）。

3. **サーバー**は、アピアランスチャネル向けに新しいサブスクリプションを開始したことを認識し、サーバーの`subscribed`コールバックを呼び出し、`current_user`の`appear`メソッドを呼び出す。（`appearance_channel.rb`）

4. **クライアント**は、サブスクリプションが確立したことを認識し、`connected`（`appearance_channel.js`）を呼び出す。これにより、`install`と`appear`が呼び出される。`appear`はサーバーの`AppearanceChannel#appear(data)`を呼び出して`{ appearing_on: this.appearingOn }`のデータハッシュを渡す。なお、この動作が可能なのは、クラスで宣言されている（コールバックを除く）全パブリックメソッドが、サーバー側のチャネルインスタンスから自動的に公開されるからです。公開されたパブリックメソッドは、サブスクリプションで`perform`メソッドを使って、RPC（リモートプロシージャコール）として利用できます。

5. **サーバー**は、`current_user`で認識したコネクションのアピアランスチャネルで、`appear`アクションへのリクエストを受信する。（`appearance_channel.rb`）**サーバー**は`:appearing_on`キーを使ってデータをデータハッシュから取り出し、
`current_user.appear`に渡される`:on`キーの値として設定する。

### 例2: 新しいweb通知を受信する

この例では、WebSocketコネクションを使って、サーバーからクライアント側の機能をリモート実行するときのアピアランスを扱います。WebSocketでは双方向通信を利用できます。そこで、例としてサーバーからクライアントでアクションを起動してみます。

このweb通知チャネルは、正しいストリームにブロードキャストを行ったときに、クライアント側でweb通知を表示します。

サーバー側のweb通知チャネルを作成します。

```ruby
# app/channels/web_notifications_channel.rb
class WebNotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
```

クライアント側のweb通知チャネルを作成します。

```js
// app/javascript/channels/web_notifications_channel.js
// クライアント側では、サーバーからweb通知の送信権を
// リクエスト済みであることが前提
import consumer from "./consumer"
consumer.subscriptions.create("WebNotificationsChannel", {
  received(data) {
    new Notification(data["title"], body: data["body"])
  }
})
```

アプリケーションのどこからでも、web通知チャネルのインスタンスにコンテンツをブロードキャストできます。

```ruby
# このコードはアプリケーションのどこか（NewCommentJob あたり）で呼び出される
WebNotificationsChannel.broadcast_to(
  current_user,
  title: 'New things!',
  body: 'All the news fit to print'
)
```

`WebNotificationsChannel.broadcast_to`呼び出しでは、現在のサブスクリプションアダプタのpubsubキューにメッセージを設定します。ユーザーごとに異なるブロードキャスト名が使われます。IDが1のユーザーなら、ブロードキャスト名は`web_notifications:1`のようになります。

このチャネルは、`web_notifications:1`に着信するものすべてを`received`コールバック呼び出しによってクライアントに直接ストリーミングするようになります。引数として渡されたデータは、サーバー側のブロードキャスト呼び出しに2番目のパラメータとして渡されたハッシュです。このハッシュはJSONでエンコードされ、`received`として受信したデータ引数から取り出されます。

### より詳しい例

RailsアプリケーションにAction Cableを設定する方法やチャネルの追加方法については、[rails/actioncable-examples](https://github.com/rails/actioncable-examples) で完全な例をご覧いただけます。

## 設定

Action Cableで必須となる設定は、「サブスクリプションアダプタ」と「許可されたリクエスト送信元」の2つです。

### サブスクリプションアダプタ

Action Cableは、デフォルトで`config/cable.yml`の設定ファイルを利用します。Railsの環境ごとに、アダプタとURLを1つずつ指定する必要があります。アダプタについて詳しくは、[依存関係](#依存関係) の節をご覧ください。

```yaml
development:
  adapter: async

test:
  adapter: async

production:
  adapter: redis
  url: redis://10.10.3.153:6381
  channel_prefix: appname_production
```

#### 利用できるアダプタ設定

以下は、エンドユーザー向けに利用できるサブスクリプションアダプタの一覧です。

##### Asyncアダプタ

`async`アダプタはdevelopment環境やtest環境での利用を意図したものであり、production環境で使うべきではありません。

##### Redisアダプタ

Redisアダプタでは、Redisサーバーを指すURLを指定する必要があります。
また、複数のアプリケーションが同一のRedisサーバーを用いる場合は、チャンネル名衝突を避けるために`channel_prefix`の指定が必要になることもあります。詳しくは[Redis PubSubドキュメント](https://redis.io/topics/pubsub#database-amp-scoping)を参照してください。

##### PostgreSQLアダプタ

PostgreSQLアダプタはActive Recordコネクションプールを用いるため、アプリケーションのデータベース設定ファイル (`config/database.yml`) でコネクションを設定します。将来変更される可能性があります。[#27214](https://github.com/rails/rails/issues/27214)

### 許可されたリクエスト送信元

Action Cableは、指定されていない送信元からのリクエストを受け付けません。送信元リストは、配列の形でサーバー設定に渡します。送信元リストには文字列のインスタンスや正規表現を利用でき、これに対して一致するかどうかがチェックされます。

```ruby
config.action_cable.allowed_request_origins = ['https://rubyonrails.com', %r{http://ruby.*}]
```

すべての送信元からのリクエストを許可または拒否するには、次を設定します。

```ruby
config.action_cable.disable_request_forgery_protection = true
```

development環境で実行中、Action Cableはlocalhost:3000からのすべてのリクエストをデフォルトで許可します。

### コンシューマーの設定

URLを設定するには、HTMLレイアウトのHEADセクションに`action_cable_meta_tag`呼び出しを追加します。通常、ここで使うURLは、環境ごとの設定ファイルで`config.action_cable.url`に設定されます。

### ワーカープールの設定

ワーカープールは、サーバーのメインスレッドから隔離された状態でコネクションのコールバックやチャネルのアクションを実行するために用いられます。Action Cableでは、アプリケーションのワーカープール内で同時に処理されるスレッド数を次のように設定できます。

```ruby
config.action_cable.worker_pool_size = 4
```

また、サーバーが提供するデータベース接続の数は、少なくとも利用するワーカー数と同じでなければなりません。デフォルトのワーカープールサイズは4に設定されているので、データベース接続数は少なくとも4以上を確保しなければなりません。この設定は`config/database.yml`の`pool`属性で変更できます。

### その他の設定

他にも、コネクションごとのロガーにタグを保存するオプションがあります。次の例は、ユーザーアカウントIDがある場合はそれを使い、ない場合は「no-account」を使うタグ付けです。

```ruby
config.action_cable.log_tags = [
  -> request { request.env['user_account_id'] || "no-account" },
  :action_cable,
  -> request { request.uuid }
]
```

利用可能なすべての設定オプションについては、`ActionCable::Server::Configuration`クラスをご覧ください。

## Action Cable専用サーバーを実行する

### アプリケーションで実行

Action CableはRailsアプリケーションと一緒に実行できます。たとえば、`/websocket`でWebSocketリクエストをリッスンするには、`config.action_cable.mount_path`でパスを指定します。

```ruby
# config/application.rb
class Application < Rails::Application
  config.action_cable.mount_path = '/websocket'
end 
```

レイアウトで`action_cable_meta_tag`が呼び出されると、`ActionCable.createConsumer()`でAction Cableサーバーに接続できるようになります。それ以外の場合は、パスが`createConsumer`の最初の引数として指定されます（例: `ActionCable.createConsumer("/websocket")`）。

作成したサーバーの全インスタンスと、サーバーが作成した全ワーカーのインスタンスには、Action Cableの新しいインスタンスも含まれます。コネクション間のメッセージ同期は、Redisによって行われます。

### スタンドアロン

アプリケーション・サーバーとAction Cableサーバーを分けることもできます。Action CableサーバーはRackアプリケーションですが、独自のRackアプリケーションでもあります。推奨される基本設定は次のとおりです。

```ruby
# cable/config.ru
require_relative '../config/environment'
Rails.application.eager_load!

run ActionCable.server
```

続いて、 `bin/cable`のbinstubを使ってサーバーを起動します。

```
#!/bin/bash
bundle exec puma -p 28080 cable/config.ru
```

ポート28080でAction Cableサーバーが起動します。

### メモ

WebSocketサーバーからはセッションにアクセスできませんが、cookieにはアクセスできます。これを利用して認証を処理できます。[Action CableとDeviseでの認証](https://greg.molnar.io/blog/actioncable-devise-authentication/) 記事をご覧ください。

## 依存関係

Action Cableは、自身のpubsub内部のプロセスへのサブスクリプションアダプタインターフェイスを提供します。非同期、インライン、PostgreSQL、Redisなどのアダプタをデフォルトで利用できます。新規Railsアプリケーションのデフォルトアダプタは非同期（`async`）アダプタです。

Ruby側では、[websocket-driver](https://github.com/faye/websocket-driver-ruby)、
[nio4r](https://github.com/celluloid/nio4r)、[concurrent-ruby](https://github.com/ruby-concurrency/concurrent-ruby)の上に構築されています。

## デプロイ

Action Cableを支えているのは、WebSocketとスレッドの組み合わせです。フレームワーク内部の流れや、ユーザー指定のチャネルの動作は、Rubyのネイティブスレッドによって処理されます。つまり、スレッドセーフを損なわない限り、Railsの正規のモデルはすべて問題なく利用できるということです。

Action Cableサーバーには、RackソケットをハイジャックするAPIが実装されています。これによって、アプリケーション・サーバーがマルチスレッドであるかどうかにかかわらず、内部のコネクションをマルチスレッドパターンで管理できます。

つまり、Action Cableは、Unicorn、Puma、Passengerなどの有名なサーバーと問題なく連携できるのです。

## テスト

Action Cableで作成した機能のテスト方法について詳しくは、[テスティングガイド](testing.html#action-cableをテストする)を参照してください。
