# 탐색 대상 경로 (. 은 현재 실행 디렉터리)
$targetPath = "."

# 대상 파일 확장자
$includeFilter = @("*.js", "*.jsx", "*.ts", "*.tsx")

# 제외할 디렉터리
$excludeDirs = @("node_modules", "dist", "build", ".next", ".git")

# 로그 파일 경로 (타임스탬프 기반 절대 경로)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFilePath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path "console_cleanup_log_$timestamp.txt"))

# 정규표현식: 구버전 호환 New-Object 사용
$pattern = '(?m)^[ \t]*console\.(log|error|warn|info|debug|trace)\((?:[^()]*|\((?:[^()]*|\([^()]*\))*\))*\)\s*;?(?:\r?\n)?'
$regex = New-Object System.Text.RegularExpressions.Regex($pattern)

# 로그 빌더 초기화
$logBuilder = New-Object System.Text.StringBuilder
[void]$logBuilder.AppendLine("================================================================================")
[void]$logBuilder.AppendLine(" [작업 시작 일시] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$logBuilder.AppendLine(" [대상 루트 경로] $([System.IO.Path]::GetFullPath($targetPath))")
[void]$logBuilder.AppendLine("================================================================================`n")

$processedFiles = @()
$totalRemovedCount = 0

# 대상 파일 순회
Get-ChildItem -Path $targetPath -Include $includeFilter -Recurse -File | Where-Object {
    $fullPath = $_.FullName
    $skip = $false
    foreach ($dir in $excludeDirs) {
        if ($fullPath -match "[\\/]$dir[\\/]") {
            $skip = $true
            break
        }
    }
    -not $skip
} | ForEach-Object {
    $fullFilePath = [System.IO.Path]::GetFullPath($_.FullName)
    $originalContent = [System.IO.File]::ReadAllText($fullFilePath, [System.Text.Encoding]::UTF8)
    
    $matches = $regex.Matches($originalContent)
    if ($matches.Count -gt 0) {
        $processedFiles += $fullFilePath
        $totalRemovedCount += $matches.Count

        # 파일별 헤더 기록
        [void]$logBuilder.AppendLine("--------------------------------------------------------------------------------")
        [void]$logBuilder.AppendLine("[파일 경로] $fullFilePath")
        [void]$logBuilder.AppendLine("[제거 건수] $($matches.Count)건")
        [void]$logBuilder.AppendLine("--------------------------------------------------------------------------------")

        # 각 매칭된 부분의 라인 번호와 실제 구문만 추출
        $matchIndex = 1
        foreach ($match in $matches) {
            # 매칭 위치 이전의 개행 문자 수를 세어 라인 번호 계산
            $substringBefore = $originalContent.Substring(0, $match.Index)
            $lineNumber = ($substringBefore -split "\r?\n").Count
            
            $removedText = $match.Value.TrimEnd("`r", "`n")

            [void]$logBuilder.AppendLine("  #$matchIndex (Line $lineNumber):")
            [void]$logBuilder.AppendLine("    [-] $removedText")
            $matchIndex++
        }
        [void]$logBuilder.AppendLine("")

        # 실제 파일 치환 및 저장
        $newContent = $regex.Replace($originalContent, '')
        [System.IO.File]::WriteAllText($fullFilePath, $newContent, [System.Text.Encoding]::UTF8)
        
        Write-Host "Cleaned ($($matches.Count) match(es)): $fullFilePath" -ForegroundColor Green
    }
}

# 작업 완료 요약 로깅
[void]$logBuilder.AppendLine("================================================================================")
[void]$logBuilder.AppendLine(" [작업 완료 일시] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$logBuilder.AppendLine(" [수정된 파일 수] $($processedFiles.Count)개")
[void]$logBuilder.AppendLine(" [총 제거된 구문] $totalRemovedCount 개")
[void]$logBuilder.AppendLine("================================================================================")

# 로그 파일 기록
[System.IO.File]::WriteAllText($logFilePath, $logBuilder.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "`n작업 완료! 수정된 파일: $($processedFiles.Count)개 (총 $totalRemovedCount 개 구문 제거)" -ForegroundColor Cyan
Write-Host "로그 파일 저장: $logFilePath" -ForegroundColor Yellow
