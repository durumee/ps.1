# 탐색할 폴더 경로 (. 은 현재 실행 경로)
$targetPath = "."

# 대상 확장자
$includeFilter = @("*.js", "*.jsx", "*.ts", "*.tsx")

# 제외할 폴더
$excludeDirs = @("node_modules", "dist", "build", ".next", ".git")

# 로그 파일 생성 경로 (실행 디렉터리에 타임스탬프 파일명으로 저장)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFilePath = [System.IO.Path]::GetFullPath((Join-Path $PWD "console_cleanup_log_$timestamp.txt"))

# 정규표현식: console 구문 + 세미콜론 선택적 매칭 + 빈 줄 정리
$pattern = '(?m)^[ \t]*console\.(log|error|warn|info|debug|trace)\((?:[^()]*|\((?:[^()]*|\([^()]*\))*\))*\)\s*;?(?:\r?\n)?'
$regex = [System.Text.RegularExpressions.Regex]::new($pattern)

# 로그 버퍼 초기화
$logBuilder = [System.Text.StringBuilder]::new()
[void]$logBuilder.AppendLine("================================================================================")
[void]$logBuilder.AppendLine(" [작업 시작] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$logBuilder.AppendLine(" [대상 루트 경로] $([System.IO.Path]::GetFullPath($targetPath))")
[void]$logBuilder.AppendLine("================================================================================`n")

$processedFiles = [System.Collections.Generic.List[string]]::new()

# 파일 검색 및 처리
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
    # 절대 경로를 포함한 전체 파일명
    $fullFilePath = [System.IO.Path]::GetFullPath($_.FullName)
    $originalContent = [System.IO.File]::ReadAllText($fullFilePath, [System.Text.Encoding]::UTF8)
    
    $matches = $regex.Matches($originalContent)
    if ($matches.Count -gt 0) {
        $processedFiles.Add($fullFilePath)
        $newContent = $regex.Replace($originalContent, '')

        # 실제 파일 수정
        [System.IO.File]::WriteAllText($fullFilePath, $newContent, [System.Text.Encoding]::UTF8)
        Write-Host "Cleaned ($($matches.Count) match(es)): $fullFilePath" -ForegroundColor Green

        # 파일별 변경 이력 상세 로깅
        [void]$logBuilder.AppendLine("################################################################################")
        [void]$logBuilder.AppendLine("[TARGET FILE PATH] $fullFilePath")
        [void]$logBuilder.AppendLine("[REMOVED COUNT]    $($matches.Count) match(es)")
        [void]$logBuilder.AppendLine("################################################################################")
        
        [void]$logBuilder.AppendLine("--- [제거된 구문 목록] ---")
        foreach ($match in $matches) {
            $trimmedMatch = $match.Value.Trim()
            [void]$logBuilder.AppendLine("  - $trimmedMatch")
        }
        [void]$logBuilder.AppendLine("")

        [void]$logBuilder.AppendLine("<<<<<<<<<< [변경 전 (Original): $fullFilePath] <<<<<<<<<<")
        [void]$logBuilder.AppendLine($originalContent)
        [void]$logBuilder.AppendLine("================================================================================")
        [void]$logBuilder.AppendLine(">>>>>>>>>> [변경 후 (Modified): $fullFilePath] >>>>>>>>>>")
        [void]$logBuilder.AppendLine($newContent)
        [void]$logBuilder.AppendLine("================================================================================`n`n")
    }
}

# 작업 완료 요약 로깅
[void]$logBuilder.AppendLine("================================================================================")
[void]$logBuilder.AppendLine(" [작업 완료] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$logBuilder.AppendLine(" [총 수정된 파일 수] $($processedFiles.Count) 개")
[void]$logBuilder.AppendLine("--------------------------------------------------------------------------------")
[void]$logBuilder.AppendLine(" [수정된 파일 전체 경로 목록]")
foreach ($path in $processedFiles) {
    [void]$logBuilder.AppendLine("  * $path")
}
[void]$logBuilder.AppendLine("================================================================================")

# 로그 파일 저장
[System.IO.File]::WriteAllText($logFilePath, $logBuilder.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "`n작업 완료! 수정된 파일: $($processedFiles.Count) 개" -ForegroundColor Cyan
Write-Host "로그 저장 경로: $logFilePath" -ForegroundColor Yellow
