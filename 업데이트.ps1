$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== 청정모임 일정/주소록 인터넷 업데이트 ==="

# 1. 다운로드 폴더에서 가장 최근 백업 파일 찾기 (이 PC는 Edge가 C:\Download에 저장함)
$folders = @("$env:USERPROFILE\Downloads", "C:\Download", "$env:USERPROFILE\Desktop")
$backup = $folders | ForEach-Object {
    Get-ChildItem "$_\청정모임_백업_*.json" -ErrorAction SilentlyContinue
} | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $backup) {
    Write-Host ""
    Write-Host "[!] 다운로드 폴더에 백업 파일이 없습니다."
    Write-Host "    먼저 '청정모임_관리.html'을 브라우저에서 열고"
    Write-Host "    [백업 저장] 버튼을 누른 뒤 다시 실행해 주세요."
    exit 1
}

Write-Host "백업 파일: $($backup.Name) ($(Get-Date $backup.LastWriteTime -Format 'yyyy-MM-dd HH:mm'))"

# 2. 일정 추출 (공개 게시)
$d = Get-Content $backup.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$schedules = @($d.schedules)
if ($schedules.Count -eq 0) {
    $schedJson = "[]"
} else {
    $schedJson = ConvertTo-Json $schedules -Depth 5 -Compress
}
Write-Host "일정 $($schedules.Count)건 추출 완료"

# 3. 주소록 암호화 (모임 비밀번호 필요)
$members = @($d.members)
$encJs = "var MEMBERS_ENC = null;"
if ($members.Count -gt 0) {
    Write-Host ""
    Write-Host "회원 주소록 $($members.Count)명을 비밀번호로 잠가서 함께 올립니다."
    $pw = Read-Host "모임 비밀번호 입력 (주소록을 올리지 않으려면 그냥 Enter)"
    if ($pw -and $pw.Length -ge 4) {
        $memJson = ConvertTo-Json $members -Depth 5 -Compress
        $plain = [System.Text.Encoding]::UTF8.GetBytes($memJson)
        $pwBytes = [System.Text.Encoding]::UTF8.GetBytes($pw)

        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $salt = New-Object byte[] 16; $rng.GetBytes($salt)

        $pbkdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $pwBytes, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $dk = $pbkdf.GetBytes(64)
        $aesKey = $dk[0..31]
        $macKey = $dk[32..63]

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $aesKey
        $aes.GenerateIV()
        $iv = $aes.IV
        $enc = $aes.CreateEncryptor()
        $ct = $enc.TransformFinalBlock($plain, 0, $plain.Length)

        $ivct = New-Object byte[] ($iv.Length + $ct.Length)
        [Array]::Copy($iv, 0, $ivct, 0, $iv.Length)
        [Array]::Copy($ct, 0, $ivct, $iv.Length, $ct.Length)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256(,[byte[]]$macKey)
        $mac = $hmac.ComputeHash($ivct)

        $encObj = '{"salt":"' + [Convert]::ToBase64String($salt) +
                  '","iv":"'   + [Convert]::ToBase64String($iv) +
                  '","ct":"'   + [Convert]::ToBase64String($ct) +
                  '","mac":"'  + [Convert]::ToBase64String($mac) + '"}'
        $encJs = "var MEMBERS_ENC = $encObj;"
        Write-Host "주소록 암호화 완료 (비밀번호를 아는 사람만 열람 가능)"
    } elseif ($pw) {
        Write-Host "[!] 비밀번호가 너무 짧습니다(4자 이상). 주소록은 이번에 올리지 않습니다."
    } else {
        Write-Host "주소록은 올리지 않습니다 (일정만 게시)."
    }
} else {
    Write-Host "백업에 회원 정보가 없어 일정만 게시합니다."
}

# 4. data.js 작성
$today = Get-Date -Format "yyyy-MM-dd"
$content = "var DATA = { `"schedules`": $schedJson };`r`nvar MADE = `"$today`";`r`n$encJs`r`n"
Set-Content -Path "$PSScriptRoot\data.js" -Value $content -Encoding UTF8

# 5. 인터넷에 올리기
Set-Location $PSScriptRoot
git add data.js
git commit -m "업데이트 ($today)" 2>$null
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
