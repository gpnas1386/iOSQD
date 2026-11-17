#!/usr/bin/env bash
# TVRemote 一键构建脚本：生成工程 -> 构建无签名 App -> 打包 IPA
# 产出可直接导入巨魔商店(TrollStore)安装的 TVRemote.ipa
set -e
cd "$(dirname "$0")"

SCHEME="TVRemote"
PROJECT="TVRemote.xcodeproj"
APP_PATH="build/Build/Products/Release-iphoneos/${SCHEME}.app"

echo "=============================================="
echo "  TVRemote 构建脚本（产出 TrollStore 用 IPA）"
echo "=============================================="

# 1. 检查 XcodeGen
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "[错误] 未检测到 XcodeGen。"
  echo "       请先安装：brew install xcodegen"
  exit 1
fi

# 2. 检查 Xcode 命令行工具
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[错误] 未检测到 xcodebuild，请先安装 Xcode。"
  exit 1
fi

# 3. 生成工程
echo "==> [1/3] 生成 Xcode 工程..."
xcodegen generate

# 4. 构建（无签名，Release）
echo "==> [2/3] 构建 App（Release, iphoneos, 无签名）..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  -quiet

if [ ! -d "$APP_PATH" ]; then
  echo "[错误] 构建失败，未找到 $APP_PATH"
  exit 1
fi

# 5. （可选）用 ldid 伪签名，若已安装
if command -v ldid >/dev/null 2>&1; then
  echo "==> 检测到 ldid，执行伪签名..."
  ldid -S "$APP_PATH/$SCHEME"
else
  echo "==> 未检测到 ldid，跳过（TrollStore 安装时会自动处理签名）"
fi

# 6. 打包 IPA
echo "==> [3/3] 打包 IPA..."
rm -rf Payload TVRemote.ipa
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry TVRemote.ipa Payload
rm -rf Payload

echo ""
echo "=============================================="
echo "  完成！产物：$(pwd)/TVRemote.ipa"
echo "=============================================="
echo "  安装方法："
echo "  1. 将 TVRemote.ipa 通过 AirDrop / 文件 / 网盘传到 iPhone"
echo "  2. 打开巨魔商店(TrollStore)，右上角 + 号导入该 IPA"
echo "  3. 点击 Install 安装，即可永久使用"
echo "=============================================="
