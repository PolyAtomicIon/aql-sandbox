#!/bin/bash
# AQL QA · запуск OWASP Juice Shop на Mac (Apple Silicon и Intel).
# Двойной клик по файлу или одна строка в Терминале — см. README.
# Первый запуск скачивает ~190 МБ, дальше работает без интернета.
# Ничего ставить заранее не нужно: скрипт кладёт рядом свою копию Node.js.

JUICE_VERSION="20.4.0"
NODE_VERSION="24.22.3"
INSTALL_DIR="$HOME/aql-juice-shop"
PORT=3000
URL="http://localhost:$PORT"

say_ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
say_step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
fail() {
  printf '\n\033[1;31m✗ %s\033[0m\n' "$*"
  printf '\nОкно можно закрыть. Если непонятно, что делать, — пришли скриншот этого окна лиду.\n'
  read -r -p "Нажми Enter, чтобы закрыть…" _
  exit 1
}

clear 2>/dev/null
echo "========================================"
echo "  AQL QA · OWASP Juice Shop $JUICE_VERSION"
echo "========================================"

say_step "Проверяю компьютер"
case "$(uname -m)" in
  arm64) CPU="arm64"; NODE_PLATFORM="darwin-arm64"; say_ok "Mac на Apple Silicon (M1/M2/M3/M4)" ;;
  x86_64) CPU="intel"; NODE_PLATFORM="darwin-x64"; say_ok "Mac на Intel" ;;
  *) fail "Непонятный процессор: $(uname -m). Пришли скриншот лиду." ;;
esac
mkdir -p "$INSTALL_DIR" || fail "Не получилось создать папку $INSTALL_DIR"

# --- Node.js: своя копия, только для Juice Shop. В систему не ставится. ---
NODE_DIR="$INSTALL_DIR/node-v$NODE_VERSION-$NODE_PLATFORM"
NODE="$NODE_DIR/bin/node"
if [[ ! -x "$NODE" ]]; then
  say_step "Скачиваю Node.js $NODE_VERSION (~50 МБ, один раз)"
  DIST="https://nodejs.org/dist/v$NODE_VERSION"
  TARBALL="node-v$NODE_VERSION-$NODE_PLATFORM.tar.gz"
  curl -fL --retry 3 --progress-bar -o "$INSTALL_DIR/$TARBALL" "$DIST/$TARBALL" \
    || fail "Не скачалось. Проверь интернет и запусти ещё раз."
  EXPECTED="$(curl -fsSL --retry 3 "$DIST/SHASUMS256.txt" | awk -v f="$TARBALL" '$2 == f {print $1}')"
  ACTUAL="$(shasum -a 256 "$INSTALL_DIR/$TARBALL" | awk '{print $1}')"
  if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
    rm -f "$INSTALL_DIR/$TARBALL"
    fail "Node.js скачался битым (контрольная сумма не совпала). Запусти ещё раз."
  fi
  tar xzf "$INSTALL_DIR/$TARBALL" -C "$INSTALL_DIR" || fail "Не распаковался Node.js. Хватает ли места на диске? Нужно ~1 ГБ."
  rm -f "$INSTALL_DIR/$TARBALL"
  xattr -dr com.apple.quarantine "$NODE_DIR" 2>/dev/null
fi
"$NODE" -v >/dev/null 2>&1 || { rm -rf "$NODE_DIR"; fail "Node.js не запускается. Запусти ещё раз."; }
say_ok "Node.js $("$NODE" -v)"

# --- Juice Shop. Сборка выходит только для Apple Silicon. На Intel берём её же
#     и меняем две детали (sqlite3, libxmljs2) на версии для Intel из их
#     официальных релизов: весь остальной Juice Shop — это JavaScript. ---
BUILD="juice-shop-${JUICE_VERSION}_node${NODE_VERSION%%.*}_darwin_arm64"
APP_DIR="$INSTALL_DIR/juice-shop-$JUICE_VERSION-$CPU"

if [[ ! -f "$APP_DIR/package.json" ]]; then
  say_step "Скачиваю Juice Shop (~140 МБ, один раз)"
  RELEASE="https://github.com/juice-shop/juice-shop/releases/download/v$JUICE_VERSION"
  ZIP="$INSTALL_DIR/$BUILD.zip"

  curl -fL --retry 3 --progress-bar -o "$ZIP" "$RELEASE/$BUILD.zip" \
    || fail "Не скачалось. Проверь интернет и запусти ещё раз."

  EXPECTED="$(curl -fsSL --retry 3 "$RELEASE/$BUILD.zip.md5" | awk '{print $1}')"
  ACTUAL="$(md5 -q "$ZIP")"
  if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
    rm -f "$ZIP"
    fail "Архив скачался битым (контрольная сумма не совпала). Запусти ещё раз."
  fi
  say_ok "Скачано и проверено"

  say_step "Распаковываю (до минуты)"
  TMP="$INSTALL_DIR/.unpack"
  rm -rf "$TMP" && mkdir -p "$TMP"
  unzip -q "$ZIP" -d "$TMP" || fail "Не распаковалось. Хватает ли места на диске? Нужно ~1 ГБ."
  INNER="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
  rm -rf "$APP_DIR"
  mv "$INNER" "$APP_DIR" && rm -rf "$TMP" "$ZIP"
  xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null

  if [[ "$CPU" == "intel" ]]; then
    say_step "Докладываю две детали для Intel"
    ABI="$("$NODE" -p 'process.versions.modules')"
    curl -fsSL --retry 3 "https://github.com/TryGhost/node-sqlite3/releases/download/v5.1.7/sqlite3-v5.1.7-napi-v6-darwin-x64.tar.gz" \
      | tar xz -C "$APP_DIR/node_modules/sqlite3" \
      || { rm -rf "$APP_DIR"; fail "Не скачалась деталь sqlite3. Проверь интернет и запусти ещё раз."; }
    curl -fsSL --retry 3 "https://github.com/marudor/libxmljs2/releases/download/v0.37.0/libxmljs2-v0.37.0-node-v$ABI-darwin-x64.tar.gz" \
      | tar xz -C "$APP_DIR/node_modules/libxmljs2" \
      || { rm -rf "$APP_DIR"; fail "Не скачалась деталь libxmljs2. Проверь интернет и запусти ещё раз."; }
    say_ok "Готово для Intel"
  fi
  say_ok "Установлено в $APP_DIR"
fi

if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  if curl -fs "$URL/rest/admin/application-version" >/dev/null 2>&1; then
    say_ok "Juice Shop уже запущен в другом окне — открываю браузер"
    open "$URL"
    exit 0
  fi
  fail "Порт $PORT занят другой программой. Закрой её (или перезагрузи Mac) и запусти ещё раз."
fi

say_step "Запускаю Juice Shop"
echo "Пока это окно открыто — Juice Shop работает. Закрыть: Ctrl+C или просто закрой окно."
echo "Через ~10 секунд откроется браузер: $URL"
(
  for _ in $(seq 1 120); do
    if curl -fs "$URL/rest/admin/application-version" >/dev/null 2>&1; then
      open "$URL"
      exit 0
    fi
    sleep 1
  done
) &

cd "$APP_DIR" || fail "Папка $APP_DIR пропала — удали $INSTALL_DIR и запусти ещё раз."
"$NODE" build/app
