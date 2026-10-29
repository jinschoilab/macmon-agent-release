# macmon-agent 설치 스크립트 (Windows, 관리자 PowerShell)
#
#   설치    : & ([scriptblock]::Create((irm https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main/install.ps1))) -Server http://수집서버:6600 -Key mpk_xxx
#   업그레이드: & ([scriptblock]::Create((irm …/install.ps1)))                    (기존 설정의 server·키 유지)
#   제거    : & ([scriptblock]::Create((irm …/install.ps1))) -Uninstall [-Purge]
#   수집 서버의 :6600/install.ps1로 받으면 -Server가 그 서버로 미리 채워진다(폐쇄망용).
#
# 서비스 대신 "시작 시 SYSTEM 계정으로 실행 + 실패 시 1분 후 재시작" 예약 작업(MacmonAgent)으로 등록한다.
param(
  [string]$Key = "",
  [string]$Server = "__MACMON_SERVER__",
  [string]$HostName = "",
  [string]$Proxy = "",
  [string]$Download = "",
  [switch]$NoStart,
  [switch]$Uninstall,
  [switch]$Purge
)
$ErrorActionPreference = "Stop"
$Fallback = "__MACMON_FALLBACK__"
# GitHub에서 받은 스크립트는 자리표시자가 그대로 남아 있다 — 서버 주소는 -Server·기존 설정으로, 바이너리는 공개 릴리스에서
if ($Server -like "__*__") { $Server = "" }
if ($Fallback -like "__*__") { $Fallback = "https://raw.githubusercontent.com/jinschoilab/macmon-agent-release/main" }
$Dir  = Join-Path $env:ProgramFiles "macmon-agent"
$Bin  = Join-Path $Dir "macmon-agent.exe"
$Conf = Join-Path $Dir "macmon-agent.conf"
$Log  = Join-Path $Dir "macmon-agent.log"
$Task = "MacmonAgent"

function Ok($m)   { Write-Host "  √ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
# scriptblock으로 실행되므로 exit 대신 throw — exit는 사용자의 PowerShell 창까지 닫는다
function Fail($m) { Write-Host "  × $m" -ForegroundColor Red; throw "macmon-agent 설치 중단: $m" }
function Step($n, $m) { Write-Host "`n[$n] $m" -ForegroundColor White }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail "관리자 권한 PowerShell에서 실행해 주세요" }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$web = @{ UseBasicParsing = $true; TimeoutSec = 15 }
if ($Proxy) { $web.Proxy = $Proxy }

function Stop-Agent {
  Stop-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue
  Get-Process macmon-agent -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Bin } | Stop-Process -Force -ErrorAction SilentlyContinue
}

if ($Uninstall) {
  Step "1/2" "예약 작업 중지·해제"
  Stop-Agent
  Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
  Ok "작업 제거"
  Step "2/2" "파일 삭제"
  # agent ID는 바이너리 옆(.macmon-agent.id)에 있다 — 남겨 두면 재설치 시 같은 호스트로 이어진다
  $idFile = Join-Path $Dir ".macmon-agent.id"
  if ($Purge -or -not (Test-Path $idFile)) { Remove-Item -Recurse -Force $Dir -ErrorAction SilentlyContinue }
  else { Get-ChildItem -Force $Dir | Where-Object { $_.Name -ne ".macmon-agent.id" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
  Ok "바이너리·설정·로그 삭제"
  if ($Purge) { Ok "agent ID까지 삭제 — 다시 설치하면 새 호스트로 등록됩니다" }
  elseif (Test-Path $idFile) { Write-Host "  agent ID($idFile)는 남겨 두었습니다 — 완전 삭제는 -Purge" }
  Write-Host "`nmacmon-agent 제거 완료" -ForegroundColor Green
  return
}

$upgrade = Test-Path $Conf
function Conf-Get($k) {
  if (-not (Test-Path $Conf)) { return "" }
  $line = Get-Content $Conf | Where-Object { $_ -match "^\s*$k\s*=" } | Select-Object -Last 1
  if ($line) { return ($line -replace "^\s*$k\s*=\s*", "").Trim() } else { return "" }
}
function Conf-Set($k, $v) {
  $lines = @(Get-Content $Conf)
  $hit = $false
  $lines = $lines | ForEach-Object { if (-not $hit -and $_ -match "^\s*$k\s*=") { $hit = $true; "$k=$v" } else { $_ } }
  if (-not $hit) { $lines += "$k=$v" }
  Set-Content -Path $Conf -Value $lines -Encoding ASCII
}

Step "1/6" "환경 확인"
$arch = switch ($env:PROCESSOR_ARCHITECTURE) { "AMD64" { "amd64" } "ARM64" { "arm64" } default { "386" } }
$asset = "macmon-agent-windows-$arch.exe"
Ok "Windows $arch → $asset"
if ($upgrade) {
  if (-not $Key)   { $Key = Conf-Get "project_access_key" }
  if (-not $Server) { $Server = Conf-Get "server" }
  if (-not $Proxy) { $Proxy = Conf-Get "proxy"; if ($Proxy) { $web.Proxy = $Proxy } }
}
if (-not $Key) { Fail "-Key <project_access_key> 가 필요합니다 (macmon UI → 에이전트 설치에서 키가 채워진 명령을 복사하세요)" }
if (-not $Server) { Fail "-Server <수집 서버 주소> 가 필요합니다 (예: -Server http://10.0.0.5:6600)" }
$Server = $Server.TrimEnd("/")
$primary = ($Server -split ",")[0].Trim().TrimEnd("/")

Step "2/6" "수집 서버 연결·키 확인 ($primary)"
try {
  $ping = Invoke-RestMethod @web -Uri "$primary/api/install/ping" -Headers @{ "X-Project-Key" = $Key }
  Ok ("연결·키 확인 — 프로젝트 #{0} {1}" -f $ping.pcode, $ping.name)
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 401) { Fail "project_access_key가 유효하지 않습니다 (재발급됐거나 오타)" }
  Write-Host "  · 방화벽에서 이 호스트 → 서버 TCP 아웃바운드를 열어 주세요 (Test-NetConnection 서버 -Port 6600)"
  Write-Host "  · 프록시 환경이면 -Proxy http://프록시:포트 를 붙여 다시 실행하세요"
  Fail "수집 서버에 연결할 수 없습니다: $primary ($($_.Exception.Message))"
}

Step "3/6" "바이너리 다운로드"
$tmp = Join-Path $env:TEMP $asset
$got = $null
$bases = @()
if ($Download) { $bases += $Download } else { $bases += "$primary/download" }
if ($Fallback) { $bases += $Fallback }
foreach ($b in $bases) {
  try { Invoke-WebRequest @web -Uri "$b/$asset" -OutFile $tmp; if ((Get-Item $tmp).Length -gt 0) { $got = $b; break } } catch { }
}
if (-not $got) { Fail "다운로드 실패: $asset" }
try {
  $sum = (Invoke-WebRequest @web -Uri "$got/$asset.sha256").Content.ToString().Split(" ")[0].Trim()
  $act = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
  if ($sum -and $sum -ne $act) { Remove-Item $tmp; Fail "체크섬 불일치 — 다운로드가 손상됐거나 변조됐습니다" }
  Ok "다운로드 + sha256 검증 ($got)"
} catch { Ok "다운로드 ($got, 체크섬 미제공)" }

Step "4/6" "설치 ($Dir)"
Stop-Agent
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Move-Item -Force $tmp $Bin
if (-not $upgrade) {
  Set-Content -Path $Conf -Encoding ASCII -Value @(
    "# macmon-agent config - generated by install.ps1 ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))",
    "server=$Server",
    "project_access_key=$Key")
  Ok "설정 생성: $Conf"
} else {
  Conf-Set "server" $Server
  Conf-Set "project_access_key" $Key
  Ok "기존 설정 유지·갱신: $Conf"
}
if ($HostName) { Conf-Set "hostname" $HostName }
if ($Proxy)    { Conf-Set "proxy" $Proxy }
# 키가 들어 있으므로 Administrators·SYSTEM만 읽기
icacls $Conf /inheritance:r /grant:r "*S-1-5-32-544:F" "*S-1-5-18:F" | Out-Null

Step "5/6" "예약 작업 등록 ($Task)"
$action    = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"`"$Bin`" >> `"$Log`" 2>&1`"" -WorkingDirectory $Dir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Ok "시작 시 SYSTEM으로 실행, 실패 시 1분 후 재시작"

Step "6/6" "시작·첫 전송 확인"
if ($NoStart) { Warn "-NoStart: 시작하지 않았습니다" }
else {
  if (Test-Path $Log) { Clear-Content $Log }
  Start-ScheduledTask -TaskName $Task
  Start-Sleep -Seconds 10
  $fail = if (Test-Path $Log) { Select-String -Path $Log -Pattern "전송 실패" -SimpleMatch | Select-Object -Last 3 } else { $null }
  if ($fail) { Warn "실행 중이지만 전송에 실패하고 있습니다:"; $fail | ForEach-Object { Write-Host "    $($_.Line)" } }
  elseif (Get-Process macmon-agent -ErrorAction SilentlyContinue) { Ok "실행 중 — UI의 설치 화면에서 수신 확인이 곧 표시됩니다" }
  else { Warn "프로세스가 떠 있지 않습니다. 로그: $Log" }
}

$what = if ($upgrade) { "업그레이드" } else { "설치" }
@"

────────────────────────────────────────────
 macmon-agent $what 완료
────────────────────────────────────────────
 설치된 파일
   바이너리  $Bin
   설정      $Conf
   로그      $Log
   작업      작업 스케줄러 > $Task
 관리
   재시작    Stop-ScheduledTask $Task; Start-ScheduledTask $Task   (설정 수정 후)
   제거      & ([scriptblock]::Create((irm $primary/install.ps1))) -Uninstall
"@ | Write-Host
