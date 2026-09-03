param([string]$Dir)

if (-not $Dir) { $Dir = Read-Host "Target Directory Path" }
$Dir = $Dir.Trim("`"' ")
if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Write-Host "Directory not found."; exit }

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
                $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "(\b[A-Za-z0-9_]*NCST_[A-Za-z0-9_]+)\b)(\s+(?i:AS\s+)?[A-Za-z0-9_]+)?", {
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

        # 라인 단위 변경 기록 (파일명 제외하고 라인 번호만)
        if ($Orig -ne $Line) {
            $FileLogs += "  Line $($i + 1):"
            $FileLogs += "    [-] $Orig"
            $FileLogs += "    [+] $Line"
        }
        $Out += $Line
    }

    # 파일명은 헤더로 상단에 1회만 추가
    if ($FileLogs.Count -gt 0) {
        Set-Content -LiteralPath $Path -Value $Out -Encoding UTF8
        $AllLogs += "[$FileName]"
        $AllLogs += $FileLogs
        $AllLogs += ""
        Write-Host "Updated: $FileName"
    }
}

if ($AllLogs.Count -gt 0) {
    Set-Content -LiteralPath $TotalLog -Value $AllLogs -Encoding UTF8
    Write-Host "Log saved to: $TotalLog"
} else {
    Write-Host "No changes detected across all files."
}
