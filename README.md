# macmon-agent

macOS / Linux 시스템 모니터링 에이전트

| 파일 | 대상 | 최소 버전 |
|------|------|-----------|
| `macmon-agent` | macOS Universal (Apple Silicon + Intel) | macOS 12.0 (Monterey) 이상 |
| `macmon-agent-legacy` | macOS Intel 전용 (구형 Mac) | macOS 10.13 (High Sierra) 이상 |
| `macmon-agent-linux-amd64` | Linux x86_64 (64bit) | — |
| `macmon-agent-linux-386` | Linux x86 (32bit) | — |
| `macmon-agent-linux-arm64` | Linux aarch64 (ARM64) — Raspberry Pi 4/5 (64bit OS) | — |
| `macmon-agent-linux-arm` | Linux armhf (ARM32) — Raspberry Pi 2/3/4 (32bit OS), Zero 2 W | — |
| `macmon-agent-windows-amd64.exe` | Windows x86_64 (64bit) | Windows 10 이상 |
| `macmon-agent-windows-386.exe` | Windows x86 (32bit) | Windows 10 이상 |
| `macmon-agent-windows-arm64.exe` | Windows ARM64 | Windows 10 이상 |
| `macmon-agent-windows7-amd64.exe` | Windows 7/8/8.1 x86_64 (64bit) | Windows 7 이상 |
| `macmon-agent-windows7-386.exe` | Windows 7/8/8.1 x86 (32bit) | Windows 7 이상 |

### Go APM (Linux 전용, macmon-agent에 내장)

Go 애플리케이션 무침투 트레이싱. eBPF uprobe로 HTTP/DB/goroutine을 코드 수정 없이 관측합니다.
**별도 바이너리 아님** — `macmon-agent-linux-amd64`/`arm64`에 포함돼 있으며 설정에서 활성화만 하면 됩니다:

두 가지 모드 중 하나로 설정합니다.

**모드 1: 명시적 대상 지정 (whitelist, 권장)**
```
collect.apm.go = true
collect.apm.go.targets = /opt/myapp/server,/opt/another/app
```

**모드 2: 자동 탐지 + 제외 (blacklist)**
```
collect.apm.go = true
collect.apm.go.auto = true
collect.apm.go.exclude = macmon-server,macmon-collector,macmon-agent
```
> `exclude`는 **basename 부분일치**. 빈 값이면 `/proc`의 모든 Go 바이너리 attach — 수집 서버(macmon-server/collector)를 절대 빼지 마세요. 자기참조 루프로 서버 과부하/OOM 발생합니다.

**특수 케이스: macmon-server 자체를 관측하고 싶을 때**
```
collect.apm.go = true
collect.apm.go.targets = /home/ubuntu/macmon/macmon-server-release/macmon-server
collect.apm.go.exclude_paths = /api/traces
```
`exclude_paths`는 루트 HTTP 경로와 **정확 일치**하는 트랜잭션만 드롭하므로 `/api/traces` 하나만 넣어도 `/api/traces/stats`, `/api/traces/{id}` 같은 UI API는 정상 수집됨.

둘 다 비워두면 APM은 동작하지 않습니다.

요구사항: Linux 커널 4.14+, `CAP_BPF` 또는 root. macOS/Windows에서는 옵션을 켜둬도 자동 무시됩니다.

> **구형 인텔 Mac 사용자** (macOS 10.13 ~ 11.x): `macmon-agent` 대신 `macmon-agent-legacy`를 사용하세요.
> Legacy 버전은 클라우드 메타데이터(AWS/GCP/Azure 등) 감지를 제외한 나머지 기능은 동일합니다.

---

### Java APM (별도 바이너리)

Java 프로세스의 HTTP/JDBC 트랜잭션을 추적합니다(JVMTI Attach 기반).
Go APM과 달리 macmon-agent에 내장되어 있지 않습니다 — 아래 두 파일을 별도로 받아야 합니다.

| 플랫폼 | attacher 바이너리 | 재시작 없이 붙기(`-pid`) | 지원 모드 |
|--------|-------------------|:---:|-----------|
| Linux (amd64) | `macmon-java-attacher-linux-amd64` | ✅ (jattach 필요) | `-pid` 특정 PID / 자동 탐지 / `-listen` |
| macOS (arm64) | `macmon-java-attacher-darwin-arm64` | ❌ | `-listen`만 (재시작 필요) |
| macOS (Intel) | `macmon-java-attacher-darwin-amd64` | ❌ | `-listen`만 (재시작 필요) |

```bash
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-java-agent.jar

# Linux
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-java-attacher-linux-amd64
chmod +x macmon-java-attacher-linux-amd64

# macOS (Apple Silicon)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-java-attacher-darwin-arm64
chmod +x macmon-java-attacher-darwin-arm64

# macOS (Intel)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-java-attacher-darwin-amd64
chmod +x macmon-java-attacher-darwin-amd64
```

#### Linux — 재시작 없이 붙이기 (권장)

**사전 준비: `jattach` 설치 필요** — attacher가 PATH에서 `jattach`를 찾아 실행합니다(내장 아님).
```bash
# github.com/jattach/jattach 릴리스에서 다운로드하거나 소스 빌드 후 PATH에 추가
curl -Lo /usr/local/bin/jattach https://github.com/jattach/jattach/releases/latest/download/jattach
chmod +x /usr/local/bin/jattach
```

**모드 1: 특정 PID 지정 (권장)**
```bash
./macmon-java-attacher-linux-amd64 -pid <대상 JVM PID> -agent macmon-java-agent.jar -endpoint http://서버IP:8280
```

**모드 2: 자동 탐지 (`-pid`/`-listen` 둘 다 생략)**
```bash
./macmon-java-attacher-linux-amd64 -agent macmon-java-agent.jar -endpoint http://서버IP:8280
```
> 5초마다 `/proc`을 스캔해 발견되는 모든 Java 프로세스에 자동으로 attach합니다. Go APM의 `exclude` 같은 제외 목록은 아직 없어서 호스트의 모든 JVM에 다 붙습니다 — 여러 Java 프로세스가 도는 호스트에선 모드 1로 원하는 프로세스만 지정하는 걸 권장합니다.

#### macOS — `-listen` 모드 (재시작 필요)

macOS는 `jattach`가 공식 지원되지 않아 **동적 attach(`-pid`) 불가** — 대신 대상 Java 프로세스를 **agent를 붙여서 재시작**하고, attacher는 소켓 수신만 합니다.

```bash
# 1. 대상 프로세스를 agent 붙여서 재시작 (소켓 이름의 숫자는 임의로 정해도 됨, 예: 9999)
JAVA_TOOL_OPTIONS="-javaagent:/path/to/macmon-java-agent.jar=socket=/tmp/macmon-java-9999.sock" \
  <원래 실행 명령> &

# 2. attacher를 -listen 모드로 실행 (숫자가 위 1번과 정확히 일치해야 함)
./macmon-java-attacher-darwin-arm64 -listen 9999 -agent macmon-java-agent.jar -endpoint http://서버IP:8280
```

**`-listen`은 정수(int) 플래그입니다** — 프로세스 이름 같은 문자열은 안 됩니다(`invalid value ... parse error`). 소켓 경로 `/tmp/macmon-java-<값>.sock`의 `<값>`이 1·2번 양쪽에서 같은 숫자면 되고, 실제 PID와 일치할 필요는 없습니다 — 대상을 특정할 목적이면 실제 PID(`ps -ef` 등으로 확인)를 쓰는 게 헷갈리지 않습니다.

#### 공통 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `-pid` | — | 대상 JVM PID. 지정하면 jattach로 주입 후 소켓 수신 (Linux 전용) |
| `-agent` | `macmon-java-agent.jar` | 주입할 에이전트 jar 경로 |
| `-endpoint` | — | macmon-server 주소. 비우면 로컬 워터폴 출력만(서버 전송 안 함) |
| `-sample` | 100 | 샘플링 비율 (1~100%) |
| `-listen` | — | **정수(int)만 허용.** jattach 없이 소켓 수신만 (Java를 `-javaagent:macmon-java-agent.jar=socket=...`로 직접 시작했을 때). macOS에서는 이 모드만 지원 |

`attacher`는 스팬을 계속 수신·전달하는 **상시 프로세스**입니다 — nohup/systemd로 macmon-agent와 함께 계속 띄워두세요. 중간에 종료하면 그 시점부터 트레이스가 끊깁니다.

요구사항: JDK(Attach API 포함 — JRE만 있으면 동작 안 함). Linux는 추가로 `jattach` PATH 등록 필요.

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

## Windows

```powershell
# 1. 바이너리 다운로드 (PowerShell)
Invoke-WebRequest -Uri https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-windows-amd64.exe -OutFile macmon-agent.exe

# 2. 설정 파일 생성
@"
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
"@ | Out-File -Encoding utf8 macmon-agent.conf

# 3. 실행
.\macmon-agent.exe

# 또는 커맨드 라인으로 바로 지정
.\macmon-agent.exe -server http://서버IP:6600 -interval 5 -hostname 내PC이름
```

> **참고**: Windows는 프로세스 CPU% 수집이 제한됩니다 (tasklist가 CPU% 미제공). 메모리 사용량은 정상 수집됩니다.

---

## Windows 7 / 8 / 8.1

Windows 10 미만 구형 환경용 별도 빌드입니다.

```powershell
# 64bit
Invoke-WebRequest -Uri https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-windows7-amd64.exe -OutFile macmon-agent.exe

# 32bit
Invoke-WebRequest -Uri https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-windows7-386.exe -OutFile macmon-agent.exe

# 설정 파일 생성
@"
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
"@ | Out-File -Encoding utf8 macmon-agent.conf

# 실행
.\macmon-agent.exe
```

**Win7 버전 제약사항:**
- 수집 항목: CPU / 메모리 / 디스크 / 네트워크 I/O / 프로세스 Top10
- 프로세스 CPU% 미수집 (tasklist 미지원)
- Java / Python / K8s / 배터리 / 시스템 로그 미수집
- 설정 파일 옵션: `server`, `interval`, `hostname` 만 지원

---

## Linux

```bash
# amd64 (x86_64)
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-linux-amd64
chmod +x macmon-agent-linux-amd64

# arm64 (aarch64) — Pi 4/5 64bit OS, Pi Zero 2 W
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-linux-arm64
chmod +x macmon-agent-linux-arm64

# arm (armhf) — Pi 2/3/4 32bit OS, Pi Zero 2 W 32bit
curl -LO https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/macmon-agent-linux-arm
chmod +x macmon-agent-linux-arm

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
# hostname          = 내PC이름  # 생략 시 OS 호스트명 사용
# collect.syslog    = false     # 시스템 에러 로그 수집 비활성화 (기본: true)
# collect.java      = true      # Java 프로세스 수집 활성화 (기본: false)
# collect.python    = true      # Python 프로세스 수집 활성화 (기본: false)
# collect.k8s       = true      # Kubernetes 파드 수집 활성화 (기본: false)
# collect.springboot = true     # Spring Boot Actuator 수집 활성화 (기본: false)
```

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `server` | http://localhost:6600 | 수집 서버 주소 |
| `interval` | 5 | 수집 주기 (초) |
| `hostname` | OS 호스트명 | 표시될 이름 |
| `collect.syslog` | true | 시스템 에러 로그 수집. `false`/`0`/`off`로 비활성화 |
| `collect.java` | false | Java 프로세스 수집. `true`/`1`/`on`으로 활성화 |
| `collect.python` | false | Python 프로세스 수집. `true`/`1`/`on`으로 활성화 |
| `collect.k8s` | false | Kubernetes 파드 수집 (kubectl 필요). `true`/`1`/`on`으로 활성화 |
| `collect.springboot` | false | Spring Boot Actuator 수집. `true`/`1`/`on`으로 활성화 |

> 기존 옵션명(`java`, `python`, `k8s`, `syslog`, `springboot.actuator`)도 하위호환으로 계속 동작합니다.

> **collect.java/python/k8s/springboot 수집은 기본적으로 비활성화**되어 있습니다. 에이전트 부하를 줄이기 위해 필요한 경우에만 활성화하세요.

## CLI 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `-server` | http://localhost:6600 | 수집 서버 URL |
| `-interval` | 5 | 수집 주기 (초) |
| `-hostname` | OS 호스트명 | 표시될 이름 |
| `-once` | — | 1회 수집 후 종료 |
| `-python` | false | Python 프로세스 수집 활성화 |
| `-k8s` | false | Kubernetes 파드 수집 활성화 |

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
