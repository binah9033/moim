$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== 청정모임 일정 인터넷 업데이트 ==="

# 1. 다운로드 폴더에서 가장 최근 백업 파일 찾기
$backup = Get-ChildItem "$env:USERPROFILE\Downloads\청정모임_백업_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $backup) {
    Write-Host ""
    Write-Host "[!] 다운로드 폴더에 백업 파일이 없습니다."
    Write-Host "    먼저 '청정모임_관리.html'을 브라우저에서 열고"
    Write-Host "    [백업 저장] 버튼을 누른 뒤 다시 실행해 주세요."
    exit 1
}

Write-Host "백업 파일: $($backup.Name) ($(Get-Date $backup.LastWriteTime -Format 'yyyy-MM-dd HH:mm'))"

# 2. 일정만 추출 (회원 주소록은 인터넷에 올리지 않음)
$d = Get-Content $backup.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$schedules = @($d.schedules)
if ($schedules.Count -eq 0) {
    $schedJson = "[]"
} else {
    $schedJson = ConvertTo-Json $schedules -Depth 5 -Compress
}
$today = Get-Date -Format "yyyy-MM-dd"
$content = "var DATA = { `"schedules`": $schedJson };`r`nvar MADE = `"$today`";`r`n"
Set-Content -Path "$PSScriptRoot\data.js" -Value $content -Encoding UTF8
Write-Host "일정 $($schedules.Count)건 추출 완료 (주소록은 제외됨)"

# 3. 인터넷에 올리기
Set-Location $PSScriptRoot
git add data.js
git commit -m "일정 업데이트 ($today)" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "변경된 내용이 없습니다. (이미 최신 상태)"
    exit 0
}
git push
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[완료] 1~2분 후 아래 주소에 반영됩니다:"
    Write-Host "       https://binah9033.github.io/moim/"
} else {
    Write-Host "[!] 인터넷 업로드에 실패했습니다. 네트워크 상태를 확인해 주세요."
    exit 1
}
