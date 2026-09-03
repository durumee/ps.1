param([string]$Path)

# 1. 파일 경로 입력 처리
if (-not $Path) { $Path = Read-Host "Target XML File Path" }
if (-not (Test-Path $Path)) { Write-Host "File not found."; exit }

$Log = [System.IO.Path]::ChangeExtension($Path, ".log.txt")
$Lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
$Out = @(); $Logs = @(); $InWhere = $false

# 7. 테이블 치환 매핑 정의 (필요 시 테이블 계속 추가)
$TblMap = @{
    "TB_CB01300M" = "TB_CB01000M /*비고객수정*/"
}

# 컬럼명 치환 함수 (규칙 6 반영)
function Rep-Col($col) {
    if ($col -match "NCST_BACNT") {
        return ($col -replace "NCST_BACNT", "BACNT")
    }
    return ($col -replace "NCST_", "CUST_" -replace "_NCST_", "_CUST_")
}

# 2~6. 라인 단위 구문 분석 및 치환
for ($i = 0; $i -lt $Lines.Count; $i++) {
    $Orig = $Lines[$i]
    $Line = $Orig
    $Trim = $Line.Trim()

    # WHERE 절 영역 감지
    if ($Trim -match "(?i)\bWHERE\b") { $InWhere = $true }
    if ($Trim -match "(?i)\b(GROUP\s+BY|ORDER\s+BY|HAVING)\b|</select>|</update>|</delete>|</insert>") { 
        $InWhere = $false 
    }

    # 7. 테이블명 치환
    foreach ($k in $TblMap.Keys) {
        if ($Line -match "\b$k\b") {
            $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "\b$k\b", $TblMap[$k])
        }
    }

    # 1. 대상 컬럼 패턴 존재 여부 확인
    if ($Line -match "(NCST_|_NCST_)") {
        if ($InWhere) {
            # 5. WHERE 절: 단순 치환 (규칙 6 우선 적용)
            $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "\b([A-Za-z0-9_]*NCST_[A-Za-z0-9_]+)\b", {
                param($m) Rep-Col $m.Value
            })
        } else {
            # 3, 4. SELECT 절: ALIAS 유무 판별 및 치환
            $Line = [System.Text.RegularExpressions.Regex]::Replace($Line, "(\b[A-Za-z0-9_]*NCST_[A-Za-z0-9_]+\b)(\s+(?i:AS\s+)?[A-Za-z0-9_]+)?", {
                param($m)
                $col = $m.Groups[1].Value
                $alias = $m.Groups[2].Value
                $newCol = Rep-Col $col

                if ($alias -and $alias.Trim() -ne "") {
                    # 3. ALIAS 존재: 컬럼만 변경하고 ALIAS 유지
                    return "$newCol$alias"
                } else {
                    # 4. ALIAS 미존재: 변경 후 기존 명칭을 AS ALIAS로 부여
                    return "$newCol AS $col"
                }
            })
        }
    }

    # 9. 변경 이력 로깅
    if ($Orig -ne $Line) {
        $Logs += "Line $($i + 1):"
        $Logs += "  [-] $Orig"
        $Logs += "  [+] $Line"
    }
    $Out += $Line
}

# 원본 덮어쓰기 및 로그 파일 저장
[System.IO.File]::WriteAllLines($Path, $Out, [System.Text.Encoding]::UTF8)
if ($Logs.Count -gt 0) {
    [System.IO.File]::WriteAllLines($Log, $Logs, [System.Text.Encoding]::UTF8)
    Write-Host "Done. Modified lines logged to: $Log"
} else {
    Write-Host "Done. No changes made."
}
