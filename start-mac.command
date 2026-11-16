#!/bin/bash
# AQL QA · запуск OWASP Juice Shop на Mac.
# Двойной клик по файлу (первый раз: правый клик → «Открыть»).
# Первый запуск скачивает ~140 МБ, дальше работает без интернета.

JUICE_VERSION="20.4.0"
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
if [[ "$(uname -m)" != "arm64" ]]; then
  fail "Это Mac на процессоре Intel — для него нет готовой сборки.
Открой онлайн-версию в браузере: https://demo.owasp-juice.shop
(подробности — в README, раздел «У меня Mac на Intel»)."
fi
say_ok "Mac на Apple Silicon (M1/M2/M3/M4)"

if ! command -v node >/dev/null 2>&1; then
  fail "Не найден Node.js.
Скачай установщик «LTS» с https://nodejs.org , установи (Далее → Далее → Готово)
и запусти этот файл ещё раз."
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
case "$NODE_MAJOR" in
  22 | 24 | 26) say_ok "Node.js $(node -v)" ;;
  *) fail "У тебя Node.js $(node -v), а нужен 22, 24 или 26.
Скачай «LTS» с https://nodejs.org и установи поверх — старая версия заменится." ;;
esac

BUILD="juice-shop-${JUICE_VERSION}_node${NODE_MAJOR}_darwin_arm64"
APP_DIR="$INSTALL_DIR/$BUILD"

if [[ ! -f "$APP_DIR/package.json" ]]; then
  say_step "Скачиваю Juice Shop (~140 МБ, один раз)"
  mkdir -p "$INSTALL_DIR" || fail "Не получилось создать папку $INSTALL_DIR"
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
  for _ in $(seq 1 90); do
    if curl -fs "$URL/rest/admin/application-version" >/dev/null 2>&1; then
      open "$URL"
      exit 0
    fi
    sleep 1
  done
) &

cd "$APP_DIR" || fail "Папка $APP_DIR пропала — удали $INSTALL_DIR и запусти ещё раз."
npm start
