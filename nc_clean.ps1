param([string]$Dir)

if (-not $Dir) { $Dir = Read-Host "Target Directory Path" }
$Dir = $Dir.Trim("`"' ")
if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Write-Host "Directory not found."; exit }

# 현재 실행 디렉토리에 단일 통합 로그 파일 지정
$TotalLog = Join-Path (Get-Location) "change_summary.log.txt"
$AllLogs = @()

$TblMap = @{
    "TB_CB01300M" = "TB_CB01000M /*비고객수정*/"
}

function Rep-Col($col) {
    if ($col -match "NCST_BACNT") { return ($col -replace "NCST_BACNT", "BACNT") }
    return ($col -replace "NCST_", "CUST_" -replace "_NCST_", "_CUST_")
}

Get-ChildItem -LiteralPath $Dir -Filter "*.xml" -File | ForEach-Object {
    $Path = $_.FullName
    $FileName = $_.Name
    if ($_.IsReadOnly) { $_.IsReadOnly = $false }
    $Lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $Out = @(); $FileLogs = @(); $InWhere = $false

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Orig = $Lines[$i]
        $Line = $Orig
        $Trim = $Line.Trim()

        if ($Trim -match "(?i)\bWHERE\b") { $InWhere = $true }
        if ($Trim -match "(?i)\b(GROUP\s+BY|ORDER\s+BY|HAVING)\b|</select>|</update>|</delete>|</insert>") { 
            $InWhere = $false 
        }

        foreach ($k in $TblMap.Keys) {
            if ($Line -match "\b$k\b") {
                $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "\b$k\b", $TblMap[$k])
            }
        }

        if ($Line -match "(NCST_|_NCST_)") {
            if ($InWhere) {
                $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "\b([A-Za-z0-9_]*NCST_[A-Za-z0-9_]+)\b", {
                    param($m) Rep-Col $m.Value
                })
            } else {
                $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "(\b[A-Za-z0-9_]*NCST_[A-Za-z0-9_]+\b)(\s+(?i:AS\s+)?[A-Za-z0-9_]+)?", {
                    param($m)
                    $col = $m.Groups[1].Value
                    $alias = $m.Groups[2].Value
                    $newCol = Rep-Col $col

                    if ($alias -and $alias.Trim() -ne "") {
                        return "$newCol$alias"
                    } else {
                        return "$newCol AS $col"
                    }
                })
            }
        }

        # 변경 이력 기록 (파일명, 라인번호, 전/후 내용)
        if ($Orig -ne $Line) {
            $FileLogs += "[$FileName] Line $($i + 1):"
            $FileLogs += "  [-] $Orig"
            $FileLogs += "  [+] $Line"
        }
        $Out += $Line
    }

    # 변경사항이 발생한 파일만 저장 및 통합 로그에 추가
    if ($FileLogs.Count -gt 0) {
        Set-Content -LiteralPath $Path -Value $Out -Encoding UTF8
        $AllLogs += $FileLogs
        $AllLogs += ""
        Write-Host "Updated: $FileName"
    }
}

# 단일 통합 로그 파일 저장
if ($AllLogs.Count -gt 0) {
    Set-Content -LiteralPath $TotalLog -Value $AllLogs -Encoding UTF8
    Write-Host "Log saved to: $TotalLog"
} else {
    Write-Host "No changes detected across all files."
}
