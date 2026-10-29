#!/usr/bin/env bash
# macmon-agent 설치 스크립트 (Linux / macOS)
#
#   설치    : curl -fsSL https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/install.sh \
#               | sudo bash -s -- --server http://수집서버:6600 --key mpk_xxx
#   업그레이드: curl -fsSL …/install.sh | sudo bash                         (기존 설정의 server·키 유지)
#   제거    : curl -fsSL …/install.sh | sudo bash -s -- --uninstall [--purge]
#   정본은 macmon-server/internal/api/installscripts/ — git.sh가 macmon-agent-release에 복사해 공개한다.
#   수집 서버의 :6600/install.sh로 받으면 --server가 그 서버로 미리 채워진다(GitHub에 못 나가는 폐쇄망용).
#
# 옵션
#   --key <mpk_…>        project_access_key (첫 설치 시 필수)
#   --server <url[,url]> 수집 서버(:6600). 쉼표로 예비 서버를 이어 쓰면 장애 시 자동 전환 (첫 설치 시 필수, 서버에서 받은 스크립트면 그 서버)
#   --hostname <name>    표시 이름 (기본: OS 호스트명)
#   --proxy <url>        아웃바운드 프록시 (폐쇄망). 예: http://10.0.0.1:3128
#   --download <url>     바이너리 받을 곳 (기본: 수집 서버 → 실패 시 GitHub)
#   --no-start           설치만 하고 서비스는 시작하지 않음
#   --uninstall          서비스·바이너리·설정 제거 (agent ID는 남김, --purge면 함께 제거)
set -euo pipefail

SERVER="__MACMON_SERVER__"
FALLBACK_BASE="__MACMON_FALLBACK__"
KEY=""
HOSTNAME_OPT=""
PROXY=""
DOWNLOAD_BASE=""
NO_START=0
UNINSTALL=0
PURGE=0
# GitHub에서 받은 스크립트는 자리표시자가 그대로 남아 있다 — 서버 주소는 --server·기존 설정으로, 바이너리는 공개 릴리스에서
case "$SERVER" in __*__) SERVER="" ;; esac
case "$FALLBACK_BASE" in __*__) FALLBACK_BASE="https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main" ;; esac

while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY="${2:-}"; shift 2 ;;
    --server) SERVER="${2:-}"; shift 2 ;;
    --hostname) HOSTNAME_OPT="${2:-}"; shift 2 ;;
    --proxy) PROXY="${2:-}"; shift 2 ;;
    --download) DOWNLOAD_BASE="${2:-}"; shift 2 ;;
    --no-start) NO_START=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge) PURGE=1; shift ;;
    -h|--help) sed -n '2,18p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done

c_ok()   { printf '\033[32m✔\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m✘\033[0m %s\n' "$*" >&2; }
step()   { printf '\n\033[1m[%s]\033[0m %s\n' "$1" "$2"; }

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Linux)
    INSTALL_DIR="/opt/macmon-agent"
    LOG_FILE="/var/log/macmon-agent.log"
    ;;
  Darwin)
    INSTALL_DIR="/usr/local/macmon-agent"
    LOG_FILE="/var/log/macmon-agent.log"
    PLIST="/Library/LaunchDaemons/io.macmon.agent.plist"
    ;;
  *) c_err "지원하지 않는 OS: $OS (Windows는 install.ps1 사용)"; exit 1 ;;
esac
BIN="$INSTALL_DIR/macmon-agent"
CONF="$INSTALL_DIR/macmon-agent.conf"
UNIT="/etc/systemd/system/macmon-agent.service"

if [ "$(id -u)" -ne 0 ]; then
  c_err "root 권한이 필요합니다. 명령 앞에 sudo를 붙여 주세요 (… | sudo bash -s -- …)"
  exit 1
fi

have() { command -v "$1" >/dev/null 2>&1; }
fetch() { # fetch <url> <out>
  if have curl; then curl -fsSL --connect-timeout 10 ${PROXY:+--proxy "$PROXY"} -o "$2" "$1"
  else wget -q -T 10 ${PROXY:+-e use_proxy=yes -e https_proxy="$PROXY" -e http_proxy="$PROXY"} -O "$2" "$1"; fi
}
fetch_stdout() { # fetch_stdout <url> [header]
  if have curl; then curl -fsS --connect-timeout 10 ${PROXY:+--proxy "$PROXY"} ${2:+-H "$2"} "$1"
  else wget -qO- -T 10 ${2:+--header="$2"} "$1"; fi
}

stop_service() {
  if [ "$OS" = "Linux" ] && have systemctl; then
    systemctl stop macmon-agent 2>/dev/null || true
  elif [ "$OS" = "Darwin" ]; then
    launchctl bootout system "$PLIST" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  fi
}

# ───────── 제거 ─────────
if [ "$UNINSTALL" = 1 ]; then
  step 1/2 "서비스 중지·등록 해제"
  stop_service
  if [ "$OS" = "Linux" ]; then
    if have systemctl; then systemctl disable macmon-agent 2>/dev/null || true; fi
    rm -f "$UNIT"; have systemctl && systemctl daemon-reload || true
  else
    rm -f "$PLIST"
  fi
  c_ok "서비스 제거"
  step 2/2 "파일 삭제"
  # agent ID는 바이너리 옆(.macmon-agent.id)에 있다 — 남겨 두면 재설치 시 같은 호스트로 이어진다
  ID_FILE="$INSTALL_DIR/.macmon-agent.id"
  if [ "$PURGE" = 1 ] || [ ! -f "$ID_FILE" ]; then
    rm -rf "$INSTALL_DIR"
  else
    find "$INSTALL_DIR" -mindepth 1 ! -name .macmon-agent.id -exec rm -rf {} + 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
  c_ok "바이너리·설정·로그 삭제"
  if [ "$PURGE" = 1 ]; then
    c_ok "agent ID까지 삭제 — 다시 설치하면 새 호스트로 등록됩니다"
  elif [ -f "$ID_FILE" ]; then
    echo "  agent ID($ID_FILE)는 남겨 두었습니다 — 재설치 시 같은 호스트로 이어집니다. 완전 삭제는 --purge"
  fi
  echo; c_ok "macmon-agent 제거 완료"
  exit 0
fi

# ───────── 설치 ─────────
UPGRADE=0
[ -f "$CONF" ] && UPGRADE=1

step 1/6 "환경 확인"
case "$OS/$ARCH" in
  Darwin/*)                     ASSET="macmon-agent" ;;   # Universal Binary (arm64+amd64)
  Linux/x86_64|Linux/amd64)     ASSET="macmon-agent-linux-amd64" ;;
  Linux/aarch64|Linux/arm64)    ASSET="macmon-agent-linux-arm64" ;;
  Linux/armv7l|Linux/armv6l)    ASSET="macmon-agent-linux-arm" ;;
  Linux/i386|Linux/i686)        ASSET="macmon-agent-linux-386" ;;
  *) c_err "지원하지 않는 아키텍처: $OS/$ARCH"; exit 1 ;;
esac
have curl || have wget || { c_err "curl 또는 wget이 필요합니다"; exit 1; }
c_ok "$OS $ARCH → $ASSET"
if [ "$OS" = "Linux" ] && ! have systemctl; then
  c_warn "systemd가 없습니다 — 바이너리·설정만 설치하고 서비스 등록은 건너뜁니다"
fi

# 업그레이드: 키·서버를 안 넘겼으면 기존 설정값을 쓴다
conf_get() { [ -f "$CONF" ] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" | tail -n1 || true; }
if [ "$UPGRADE" = 1 ]; then
  [ -z "$KEY" ] && KEY="$(conf_get project_access_key)"
  [ -z "$SERVER" ] && SERVER="$(conf_get server)"
  [ -z "$PROXY" ] && PROXY="$(conf_get proxy)"
fi
if [ -z "$KEY" ]; then
  c_err "--key <project_access_key> 가 필요합니다 (macmon UI → 에이전트 설치에서 키가 채워진 명령을 복사하세요)"
  exit 1
fi
if [ -z "$SERVER" ]; then
  c_err "--server <수집 서버 주소> 가 필요합니다 (예: --server http://10.0.0.5:6600)"
  exit 1
fi
SERVER="${SERVER%/}"
PRIMARY="${SERVER%%,*}"

step 2/6 "수집 서버 연결·키 확인 ($PRIMARY)"
# 설치 전에 포트 6600 도달성과 키 유효성을 한 번에 확인 — 틀린 키로 설치돼 조용히 401만 쌓이는 일을 막는다
PING="$(fetch_stdout "$PRIMARY/api/install/ping" "X-Project-Key: $KEY" 2>&1)" || {
  if printf '%s' "$PING" | grep -q 401; then
    c_err "project_access_key가 유효하지 않습니다 (재발급됐거나 오타). UI에서 키를 다시 확인하세요"
  else
    c_err "수집 서버에 연결할 수 없습니다: $PRIMARY"
    echo "  · 방화벽에서 이 호스트 → 서버 TCP ${PRIMARY##*:} 아웃바운드를 열어 주세요"
    echo "  · 프록시 환경이면 --proxy http://프록시:포트 를 붙여 다시 실행하세요"
    echo "  · 직접 확인: curl -v $PRIMARY/api/install/ping"
  fi
  exit 1
}
PROJECT_NAME="$(printf '%s' "$PING" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
PCODE="$(printf '%s' "$PING" | sed -n 's/.*"pcode":\([0-9]*\).*/\1/p')"
c_ok "연결·키 확인 — 프로젝트 #${PCODE:-?} ${PROJECT_NAME:-}"

step 3/6 "바이너리 다운로드"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GOT=""
for base in ${DOWNLOAD_BASE:-"$PRIMARY/download"} "$FALLBACK_BASE"; do
  [ -z "$base" ] && continue
  if fetch "$base/$ASSET" "$TMP/$ASSET" 2>/dev/null && [ -s "$TMP/$ASSET" ]; then GOT="$base"; break; fi
done
[ -n "$GOT" ] || { c_err "다운로드 실패: $ASSET"; exit 1; }
# 체크섬: 수집 서버가 sha256을 제공하면 검증 (GitHub 폴백은 체크섬 없음)
if SUM="$(fetch_stdout "$GOT/$ASSET.sha256" 2>/dev/null)" && [ -n "$SUM" ]; then
  if have sha256sum; then ACT="$(sha256sum "$TMP/$ASSET" | cut -d' ' -f1)"; else ACT="$(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)"; fi
  [ "${SUM%% *}" = "$ACT" ] || { c_err "체크섬 불일치 — 다운로드가 손상됐거나 변조됐습니다"; exit 1; }
  c_ok "다운로드 + sha256 검증 ($GOT)"
else
  c_ok "다운로드 ($GOT, 체크섬 미제공)"
fi

step 4/6 "설치 ($INSTALL_DIR)"
stop_service
# 수동 설치(~/macmon/에서 nohup 등)로 돌던 에이전트를 찾는다. 에이전트는 ID를 바이너리 옆에 먼저 두므로
# 홈만 봐서는 못 찾고, 그대로 두면 새 서비스와 둘이 동시에 전송한다
LEGACY_PIDS=""
LEGACY_DIRS=""
for pid in $(pgrep -x macmon-agent 2>/dev/null); do
  if [ -e "/proc/$pid/exe" ]; then
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null | sed 's/ (deleted)$//' || true)"   # d.sh처럼 rm 후 재다운로드했으면 (deleted)
  else
    exe="$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1 || true)"
  fi
  [ "$exe" = "$BIN" ] && continue
  LEGACY_PIDS="$LEGACY_PIDS $pid"
  [ -n "$exe" ] && LEGACY_DIRS="$LEGACY_DIRS $(dirname "$exe")"
done
LEGACY_HOMES="${SUDO_USER:+$(eval echo ~"$SUDO_USER")} $(eval echo ~root)"
for h in $LEGACY_HOMES; do LEGACY_DIRS="$LEGACY_DIRS $h/macmon"; done   # 멈춰 있는 수동 설치(README 경로)
if [ -n "$LEGACY_PIDS" ]; then
  kill $LEGACY_PIDS 2>/dev/null || true
  sleep 2
  kill -9 $LEGACY_PIDS 2>/dev/null || true
  c_ok "수동 실행 중이던 에이전트 종료 (PID:$LEGACY_PIDS)"
  for h in $LEGACY_HOMES; do
    if crontab -l -u "$(basename "$h")" 2>/dev/null | grep -q macmon-agent; then
      c_warn "crontab($(basename "$h"))에 macmon-agent 항목이 있습니다 — 지우지 않으면 재부팅 때 수동 에이전트가 다시 뜹니다"
    fi
  done
fi
mkdir -p "$INSTALL_DIR"
install -m 0755 "$TMP/$ASSET" "$BIN"
# 기존 agent ID를 이어받는다 — 새 UUID가 생겨 같은 호스트가 둘로 보이는 것 방지. 에이전트와 같은 우선순위(바이너리 옆 → 홈)
if [ ! -f "$INSTALL_DIR/.macmon-agent.id" ]; then
  for f in $(for d in $LEGACY_DIRS; do echo "$d/.macmon-agent.id"; done) $(for h in $LEGACY_HOMES; do echo "$h/.macmon-agent.id"; done); do
    if [ -s "$f" ]; then cp "$f" "$INSTALL_DIR/.macmon-agent.id"; c_ok "기존 agent ID 이어받음 ($f)"; break; fi
  done
fi
# 처음 설치인데 수동 설치 설정 파일이 있으면 그걸 바탕으로 한다 (hostname·DB 수집·api_key 등 보존, server·키만 아래에서 갱신)
if [ "$UPGRADE" = 0 ]; then
  for f in $(for d in $LEGACY_DIRS; do echo "$d/macmon-agent.conf"; done) $(for h in $LEGACY_HOMES; do echo "$h/.macmon-agent.conf"; done); do
    if [ -s "$f" ]; then cp "$f" "$CONF"; UPGRADE=1; c_ok "기존 설정 이어받음 ($f)"; break; fi
  done
fi
[ "$OS" = "Darwin" ] && xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
conf_set() { # conf_set <key> <value>: 있으면 교체, 없으면 추가 (다른 줄·주석은 보존)
  if grep -qE "^[[:space:]]*$1[[:space:]]*=" "$CONF"; then
    local tmp; tmp="$(mktemp)"
    awk -v k="$1" -v v="$2" 'BEGIN{d=0} { if (!d && $0 ~ "^[[:space:]]*"k"[[:space:]]*=") { print k"="v; d=1 } else print }' "$CONF" > "$tmp" && cat "$tmp" > "$CONF" && rm -f "$tmp"
  else
    echo "$1=$2" >> "$CONF"
  fi
}
if [ "$UPGRADE" = 0 ]; then
  cat > "$CONF" <<EOF
# macmon-agent 설정 — 설치 스크립트가 생성 ($(date '+%Y-%m-%d %H:%M'))
# 전체 옵션: macmon UI → 문서 → 에이전트 설치. 수정 후 서비스 재시작 필요
server=$SERVER
project_access_key=$KEY
EOF
  c_ok "설정 생성: $CONF"
else
  conf_set server "$SERVER"
  conf_set project_access_key "$KEY"
  c_ok "기존 설정 유지·갱신: $CONF"
fi
[ -n "$HOSTNAME_OPT" ] && conf_set hostname "$HOSTNAME_OPT"
[ -n "$PROXY" ] && conf_set proxy "$PROXY"
chmod 600 "$CONF"   # 키가 들어 있으므로 root만 읽기

step 5/6 "서비스 등록"
if [ "$OS" = "Linux" ] && have systemctl; then
  cat > "$UNIT" <<EOF
[Unit]
Description=macmon agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN
Restart=always
RestartSec=5
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
# 에이전트 자기 부하 상한 — 호스트 업무에 영향 주지 않도록
Nice=10
MemoryMax=300M

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable macmon-agent >/dev/null 2>&1
  c_ok "systemd 유닛: $UNIT (부팅 시 자동 시작, 비정상 종료 시 5초 후 재시작)"
elif [ "$OS" = "Darwin" ]; then
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.macmon.agent</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>WorkingDirectory</key><string>$INSTALL_DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG_FILE</string>
  <key>StandardErrorPath</key><string>$LOG_FILE</string>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
EOF
  chmod 644 "$PLIST"
  c_ok "LaunchDaemon: $PLIST (부팅 시 자동 시작, 종료 시 재시작)"
fi

step 6/6 "시작·첫 전송 확인"
if [ "$NO_START" = 1 ]; then
  c_warn "--no-start: 서비스를 시작하지 않았습니다"
else
  : > "$LOG_FILE"
  if [ "$OS" = "Linux" ] && have systemctl; then
    systemctl restart macmon-agent
  elif [ "$OS" = "Darwin" ]; then
    launchctl bootstrap system "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"
  else
    nohup "$BIN" >> "$LOG_FILE" 2>&1 &
  fi
  # 첫 메트릭은 기동 직후 전송된다. 10초 안에 "전송 실패" 로그가 없고 프로세스가 살아 있으면 성공으로 본다
  i=0
  while [ "$i" -lt 10 ]; do
    sleep 1; i=$((i + 1))
    grep -q "전송 실패" "$LOG_FILE" 2>/dev/null && break
  done
  if grep -q "전송 실패" "$LOG_FILE" 2>/dev/null; then
    c_warn "에이전트는 실행 중이지만 전송에 실패하고 있습니다:"
    grep "전송 실패" "$LOG_FILE" | tail -n 3 | sed 's/^/    /'
  elif pgrep -f "$BIN" >/dev/null; then
    c_ok "실행 중 — UI의 설치 화면에서 수신 확인이 곧 표시됩니다"
  else
    c_warn "프로세스가 떠 있지 않습니다. 로그를 확인하세요: tail -n 50 $LOG_FILE"
  fi
fi

if [ "$UPGRADE" = 1 ]; then ACTION="업그레이드"; else ACTION="설치"; fi
cat <<EOF

────────────────────────────────────────────
 macmon-agent $ACTION 완료
────────────────────────────────────────────
 설치된 파일
   바이너리  $BIN
   설정      $CONF
   로그      $LOG_FILE
EOF
if [ "$OS" = "Linux" ]; then
cat <<EOF
   서비스    $UNIT
 관리
   상태      systemctl status macmon-agent
   재시작    sudo systemctl restart macmon-agent   (설정 수정 후)
EOF
else
cat <<EOF
   서비스    $PLIST
 관리
   상태      sudo launchctl print system/io.macmon.agent | head
   재시작    sudo launchctl kickstart -k system/io.macmon.agent
   GPU/전력  sudoers에 NOPASSWD powermetrics 추가 시 수집 (UI → 에이전트 설정 참고)
EOF
fi
cat <<EOF
   업그레이드 curl -fsSL $PRIMARY/install.sh | sudo bash
   제거      curl -fsSL $PRIMARY/install.sh | sudo bash -s -- --uninstall
EOF
