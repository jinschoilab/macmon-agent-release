# macmon-agent

macOS / Linux 시스템 모니터링 에이전트

| 파일 | 대상 |
|------|------|
| `macmon-agent` | macOS (Apple Silicon + Intel Universal Binary) |
| `macmon-agent-linux-amd64` | Linux x86_64 |
| `macmon-agent-linux-arm64` | Linux aarch64 (ARM) |

---

## macOS

```bash
# 1. 바이너리 다운로드
curl -LO https://github.com/jinschoilab/macmon-agent-release/raw/main/macmon-agent
chmod +x macmon-agent

# 2. 설정 파일 생성
cat > macmon-agent.conf << 'EOF'
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
EOF

# 3. 실행
./macmon-agent
```

---

## Linux

```bash
# amd64 (x86_64)
curl -LO https://github.com/jinschoilab/macmon-agent-release/raw/main/macmon-agent-linux-amd64
chmod +x macmon-agent-linux-amd64

# arm64 (aarch64)
curl -LO https://github.com/jinschoilab/macmon-agent-release/raw/main/macmon-agent-linux-arm64
chmod +x macmon-agent-linux-arm64

# 설정 파일 생성
cat > macmon-agent.conf << 'EOF'
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
EOF

# 실행 (amd64 예시)
./macmon-agent-linux-amd64
```

---

## 설정 파일 옵션

바이너리와 같은 디렉토리의 `macmon-agent.conf` 또는 `~/.macmon-agent.conf` 를 읽습니다.

```
server   = http://서버IP:6600   # 수집 서버 주소
interval = 5                    # 수집 주기 (초)
# hostname = 내PC이름           # 생략 시 OS 호스트명 사용
```

## CLI 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `-server` | http://localhost:6600 | 수집 서버 URL |
| `-interval` | 5 | 수집 주기 (초) |
| `-hostname` | OS 호스트명 | 표시될 이름 |
| `-once` | — | 1회 수집 후 종료 |

CLI 옵션은 설정 파일보다 우선합니다.

---

## macOS GPU/ANE 수집 (Apple Silicon)

powermetrics 실행 권한이 필요합니다. `/etc/sudoers`에 추가:

```
사용자명 ALL=(ALL) NOPASSWD: /usr/bin/powermetrics
```
