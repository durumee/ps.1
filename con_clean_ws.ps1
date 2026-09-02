# 탐색 대상 경로 (. 은 현재 실행 경로)
$targetPath = "."

# 웹스퀘어 화면 파일 확장자
$includeFilter = @("*.xml")

# 제외 디렉터리
$excludeDirs = @(".git", "target", "build", "WEB-INF", ".settings")

# 로그 파일 경로 설정
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFilePath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path "websquare_console_log_$timestamp.txt"))

# 1. 정규표현식 객체 생성 (::new)
$cdataPattern = '(?s)<!\[CDATA\[(.*?)\]\]>'
$cdataRegex = [System.Text.RegularExpressions.Regex]::new($cdataPattern)

# 이미 주석 처리되었거나 변형된 구문(c_o_n_s_o_l_e)은 제외하고 실제 동작하는 console 구문만 매칭
$consolePattern = '(?<!\/\*.*)console\.(log|error|warn|info|debug|trace)\((?:[^()]*|\((?:[^()]*|\([^()]*\))*\))*\)\s*;?'
$consoleRegex = [System.Text.RegularExpressions.Regex]::new($consolePattern)

# 로그 버퍼 초기화 (::new)
$logBuilder = [System.Text.StringBuilder]::new()
[void]$logBuilder.AppendLine("================================================================================")
[void]$logBuilder.AppendLine(" [작업 시작] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$logBuilder.AppendLine(" [대상 루트 경로] $([System.IO.Path]::GetFullPath($targetPath))")
[void]$logBuilder.AppendLine("================================================================================`n")

# 작업 대상 목록 초기화 (::new)
$processedFiles = [System.Collections.Generic.List[string]]::new()

# XML 파일 순회
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
    $originalXml = [System.IO.File]::ReadAllText($fullFilePath, [System.Text.Encoding]::UTF8)

    # op_Addition 에러 방지용 리스트 객체 생성 (::new)
    $fileMatches = [System.Collections.Generic.List[psobject]]::new()

    # CDATA 내부만 탐색하여 자바스크립트 코드 치환
    $newXml = $cdataRegex.Replace($originalXml, [System.Text.RegularExpressions.MatchEvaluator]{
        param($cdataMatch)
        
        $cdataInnerCode = $cdataMatch.Groups[1].Value
        $cdataStartOffset = $cdataMatch.Groups[1].Index

        # CDATA 내부에서 console 구문 검출
        $matchesInCdata = $consoleRegex.Matches($cdataInnerCode)
        if ($matchesInCdata.Count -gt 0) {
            foreach ($m in $matchesInCdata) {
                # XML 전체 기준 절대 위치를 계산하여 실제 라인 번호 산출
                $absIndex = $cdataStartOffset + $m.Index
                $prefix = $originalXml.Substring(0, $absIndex)
                $lineNum = ($prefix -split "\r?\n").Count
                
                # console 단어를 변형(c_o_n_s_o_l_e)하여 문자열 검색 방지
                $rawText = $m.Value.Trim()
                $obfuscatedText = $rawText -replace 'console\.', 'c_o_n_s_o_l_e.'

                # 리스트에 객체 추가 (.Add)
                $fileMatches.Add([PSCustomObject]@{
                    LineNum        = $lineNum
                    RawText        = $rawText
                    TransformedText = "/* $obfuscatedText */ void 0"
                })
            }

            # CDATA 코드 치환: console 단어를 c_o_n_s_o_l_e로 바꾸고 /* ... */ void 0 처리
            $replacedCode = $consoleRegex.Replace($cdataInnerCode, [System.Text.RegularExpressions.MatchEvaluator]{
                param($mCode)
                $obfuscated = $mCode.Value -replace 'console\.', 'c_o_n_s_o_l_e.'
                return "/* $obfuscated */ void 0"
            })

            return "<![CDATA[" + $replacedCode + "]]>"
        }

        return $cdataMatch.Value
    })

    # 변경 사항이 있는 경우만 파일 쓰기 및 로깅
    if ($fileMatches.Count -gt 0) {
        $processedFiles.Add($fullFilePath)
        [System.IO.File]::WriteAllText($fullFilePath, $newXml, [System.Text.Encoding]::UTF8)
        Write-Host "Obfuscated & Commented ($($fileMatches.Count) match(es)): $fullFilePath" -ForegroundColor Green

        [void]$logBuilder.AppendLine("################################################################################")
        [void]$logBuilder.AppendLine("[TARGET FILE PATH] $fullFilePath")
        [void]$logBuilder.AppendLine("[MODIFIED COUNT]   $($fileMatches.Count) match(es)")
        [void]$logBuilder.AppendLine("################################################################################")
        [void]$logBuilder.AppendLine("--- [치환 내역 (console 변형 + 단독 if문 보호 void 0 적용)] ---")

        $idx = 1
        foreach ($item in $fileMatches) {
            [void]$logBuilder.AppendLine("  [$idx] (Line $($item.LineNum)):")
            [void]$logBuilder.AppendLine("    [-] Before: $($item.RawText)")
            [void]$logBuilder.AppendLine("    [+] After : $($item.TransformedText)")
            $idx++
        }
        [void]$logBuilder.AppendLine("`n")
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
