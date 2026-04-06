# macmon-agent

macOS 시스템 모니터링 에이전트 (Apple Silicon / Intel 지원)

## 설치 및 실행

아래 스크립트를 저장하고 실행하면 자동으로 다운로드 및 설정됩니다.

```bash
curl -fsSL https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/install.sh | bash
```

또는 직접:

```bash
# 1. 다운로드
git clone https://github.com/jinschoilab/macmon-agent-release.git
cd macmon-agent-release

# 2. 실행 권한
chmod +x macmon-agent

# 3. 실행
./macmon-agent -server http://서버IP:6600
```

## 설정 파일

바이너리와 같은 디렉토리에 `macmon-agent.conf` 생성:

```
server   = http://서버IP:6600
interval = 5
# hostname = 내PC이름
```

## 옵션

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `-server` | http://localhost:6600 | 수집 서버 URL |
| `-interval` | 5 | 수집 주기 (초) |
| `-hostname` | OS 호스트명 | 표시될 이름 |
| `-once` | false | 1회 수집 후 종료 |
