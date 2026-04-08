# macmon-agent

macOS / Linux 시스템 모니터링 에이전트

| 파일 | 대상 | 최소 버전 |
|------|------|-----------|
| `macmon-agent` | macOS Universal (Apple Silicon + Intel) | macOS 12.0 (Monterey) 이상 |
| `macmon-agent-legacy` | macOS Intel 전용 (구형 Mac) | macOS 10.13 (High Sierra) 이상 |
| `macmon-agent-linux-amd64` | Linux x86_64 | — |
| `macmon-agent-linux-arm64` | Linux aarch64 (ARM) | — |
| `macmon-agent-windows-amd64.exe` | Windows x86_64 | Windows 10 이상 |
| `macmon-agent-windows-arm64.exe` | Windows ARM64 | Windows 10 이상 |

> **구형 인텔 Mac 사용자** (macOS 10.13 ~ 11.x): `macmon-agent` 대신 `macmon-agent-legacy`를 사용하세요.
> Legacy 버전은 클라우드 메타데이터(AWS/GCP/Azure 등) 감지를 제외한 나머지 기능은 동일합니다.

---

## macOS

```bash
# 1. 바이너리 다운로드
# macOS 12.0 이상 (Apple Silicon 또는 Intel)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent
chmod +x macmon-agent

# macOS 10.13 ~ 11.x Intel Mac (구형)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-legacy
chmod +x macmon-agent-legacy

# 2. 설정 파일 생성
cat > macmon-agent.conf << 'EOF'
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
EOF

# 3. 실행 (설정 파일 사용)
./macmon-agent

# 또는 커맨드 라인으로 바로 지정
./macmon-agent -server http://서버IP:6600 -interval 5 -hostname 내PC이름
```

---

## Linux

```bash
# amd64 (x86_64)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-linux-amd64
chmod +x macmon-agent-linux-amd64

# arm64 (aarch64)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-linux-arm64
chmod +x macmon-agent-linux-arm64

# 설정 파일 생성
cat > macmon-agent.conf << 'EOF'
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
EOF

# 실행 (설정 파일 사용)
./macmon-agent-linux-amd64

# 또는 커맨드 라인으로 바로 지정
./macmon-agent-linux-amd64 -server http://서버IP:6600 -interval 5 -hostname 내서버이름
```

---

## 설정 파일 옵션

바이너리와 같은 디렉토리의 `macmon-agent.conf` 또는 `~/.macmon-agent.conf` 를 읽습니다.

```
server   = http://서버IP:6600   # 수집 서버 주소
interval = 5                    # 수집 주기 (초)
# hostname = 내PC이름           # 생략 시 OS 호스트명 사용
# syslog = false                # 시스템 에러 로그 수집 비활성화 (기본: true)
```

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `server` | http://localhost:6600 | 수집 서버 주소 |
| `interval` | 5 | 수집 주기 (초) |
| `hostname` | OS 호스트명 | 표시될 이름 |
| `syslog` | true | 시스템 에러 로그 수집. `false`/`0`/`off`로 비활성화 |

## CLI 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `-server` | http://localhost:6600 | 수집 서버 URL |
| `-interval` | 5 | 수집 주기 (초) |
| `-hostname` | OS 호스트명 | 표시될 이름 |
| `-once` | — | 1회 수집 후 종료 |

CLI 옵션은 설정 파일보다 우선합니다.

---

## Java 프로세스 모니터링

Java 힙/GC 정보 수집을 위해 `jps`, `jstat`이 필요합니다 (JDK 포함).

**Linux — JDK가 없는 경우 (JRE만 설치된 경우):**
```bash
# Java 17 기준
sudo apt install -y openjdk-17-jdk-headless

# 설치 확인
jps -l
```

JRE(`java`)만 있고 JDK(`jps`, `jstat`)가 없으면 Java 모니터링 항목은 표시되지 않습니다.

---

## macOS GPU/ANE 수집 (Apple Silicon)

powermetrics 실행 권한이 필요합니다. `/etc/sudoers`에 추가:

```
사용자명 ALL=(ALL) NOPASSWD: /usr/bin/powermetrics
```
