# cpsb

Package builder for the cpsi Package Manager

## Usage

| 使用方法 | 動作説明 |
| -------- | -------- |
| `cpsb make [FILE]` | 指定されたファイルを\*.hbだと想定してビルドします |
| `cpsb build` | 現在のディレクトリに存在する\*.hbを元にすべてのパッケージのBlake3Sumを生成し、cpsiとcpsbのみが理解できるパッケージリストを作成します |
| `cpsb version` | cpsbのバージョン情報を出力します |
| `cpsb help` | cpsbのhelpを出力します |

`cpsb make [FILE]` を使用すると、指定された\*.hbファイルからパッケージをビルドします。
\*.hbファイルの内容は、特定の関数が記述されているシェルスクリプトです。
cpsbは\*.hbファイルに以下の関数が存在することを期待しています。

| 関数名         | 期待される処理                                                        |
| ----------- | -------------------------------------------------------------- |
| build()     | パッケージをビルドする処理です。後述する変数を使用してビルド処理が記述されている必要があります                |
| package()   | パッケージを後述する`PACKAGE_DIR`へインストールする処理を記述します                       |
| pre_inst()  | パッケージをインストールする前に実行される処理です。これはcpsiパッケージマネージャーによってインストール前に実行されます |
| post_inst() | パッケージがインストールされた後に実行される処理です。これもcpsiパッケージマネージャーによって実行されます        |
| pre_rm()    | パッケージを削除する前に実行される処理です。これもcpsiパッケージマネージャー側で実行されます               |
| post_rm()   | パッケージを削除した後に実行される処理です。これもcpsiパッケージマネージャー側で実行されます               |

---

cpsbは\*.hbファイルに以下の変数が存在することも期待しています。
これらの変数は`cpsb build`または`cpsb make [FILE] `時にすべて必須で、存在しない場合cpsbはエラーを発生させます。

| 変数名           | 記入すべき情報                                   |
| ------------- | ----------------------------------------- |
| NAME          | パッケージの名称                                  |
| DEPENDS       | パッケージが依存しているパッケージ                         |
| BUILD_DEPENDS | ビルド時に必要な依存関係                              |
| DESC          | パッケージの概要                                  |
| LICENSE       | パッケージのライセンス                               |
| SOURCE        | パッケージのソースコード（cpsbはここで指定されたファイルをダウンロードします） |
| VERSION       | パッケージのバージョン                               |
| IS_BUILD      | このパッケージがビルド専用かどうか                         |

---

さらに、cpsbは`cpsb make [FILE]`時にシェルスクリプトへ以下の変数を提供します。

| 変数名         | 内容物  | 用途 |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -- |
| PACKAGE_DIR | パッケージ化に使用するディレクトリ | cpsbが生成する*.closパッケージはtar.zstd形式です。このディレクトリにパッケージをインストールしてください。圧縮とパッケージ化はcpsbが行います。                                                                                   |    |
| BUILD_DIR   | ビルドに使用する作業ディレクトリ | cpsbは自動でビルド専用ディレクトリに移動しません。`SOURCE`変数で指定したソースコードを解凍する場合、このディレクトリを解凍先として利用してください。これを使用しない場合、現在の作業ディレクトリが汚れる可能性があります。<br>build()関数の先頭で `cd "$BUILD_DIR"` を記述することを推奨します。|
| SOURCE_FILE | `SOURCE`変数で指定したURLから取得されたファイルへのパス | 多くのスクリプトでは、このファイルをbuild()関数で`BUILD_DIR`へ解凍してビルドし、package()関数で`PACKAGE_DIR`へインストールします。|

---

### *.hb Example

(cpsiのhbファイル）

```sh
#!/usr/bin/env sh
NAME="cpsi"
DEPENDS=""
BUILD_DEPENDS="curl busybox"
DESC="Package Manager for Shary OS"
LICENSE="BSD-3-Clause License"
VERSION="0.1.0.1.0"
SOURCE="https://github.com/flora-cast/cpsi/archive/refs/tags/${VERSION}.tar.gz"
IS_BUILD="false"

build() {
  mkdir -p "${BUILD_DIR}/src"
  mkdir -p "${BUILD_DIR}/zig"
  tar -xvf "${SOURCE_FILE}" -C "${BUILD_DIR}"

  curl -SfL https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz -o "${BUILD_DIR}/zig.tar.xz"
    tar -xvf "${BUILD_DIR}/zig.tar.xz" -C "${BUILD_DIR}/zig"

    cd "${BUILD_DIR}/cpsi-${VERSION}" && PATH="${BUILD_DIR}/zig/zig-x86_64-linux-0.15.2:$PATH" make
}

package() {
  cd "${BUILD_DIR}/cpsi-${VERSION}" && PREFIX="${PACKAGE_DIR}" make install
}

pre_inst() {
  :
}

post_inst() {
  :
}

pre_rm() {
  :
}

post_rm() {
  :
}

```

詳細な使用例は、flora-cast の公式パッケージリストである
[core](https://github.com/flora-cast/core) リポジトリ を参考にしてください。

