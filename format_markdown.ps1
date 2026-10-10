param(
    [string]$SourceDir = "F:\Books\Serat Centhini\en - translation",
    [string]$OutputDir = "F:\Books\Serat Centhini\en - translation"
)

$meterPattern = '^(Sinom|Gambuh|Pocung|Dhandhanggula|Asmaradana|Mijil|Kinanthi|Maskumambang|Pangkur|Durma|Wirangrong|Balabak|Pucung|Megatruh)\s+\d+\.?'
$files = Get-ChildItem $SourceDir -Filter "centhini*.txt" | Where-Object { $_.Name -notmatch 'intro' } | Sort-Object Name

foreach ($file in $files) {
    Write-Host "Processing $($file.Name)..." -NoNewline
    $raw = Get-Content $file.FullName -Raw
    
    # ---- PASS 1: Remove artifacts ----
    $raw = $raw -replace '(?m)^<\s*$', ''
    $raw = $raw -replace '(?m)^>\s*$', ''
    $raw = $raw -replace '(?m)^Serat Centhini Jilid.*$', ''
    $raw = $raw -replace '< Serat Centhini Jilid.*?>', ''
    $raw = $raw -replace 'Jilid \d+ - Kaca : \d+', ''
    $raw = $raw -replace '(?m)^[kK]aca [\d\-,\.\s]+\.?\s*$', ''
    $raw = $raw -replace '(?m)^\.\.\.\s*$', ''
    $raw = $raw -replace '[ \t]+`r`n', "`n"
    $raw = $raw -replace '[ \t]+`n', "`n"
    
    $lines = $raw -split "`r`n|`n"
    
    # ---- PASS 2: Pre-process lines ----
    # Handle stanza numbers embedded in verse lines (e.g., "...||6." or "...||  13.")
    # And handle split lines (continuation of a verse line on next line after page break)
    $processed = [System.Collections.Generic.List[string]]::new()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()
        if ($trimmed -eq "") { continue }
        
        # Check for embedded stanza number after || at end of line
        if ($trimmed -match '(.*\|\|)\s*(\d+\.?)\s*$') {
            # Split into verse content + stanza number
            $verse = $matches[1].Trim()
            $num = $matches[2]
            if ($verse -ne "") { $processed.Add($verse) }
            $processed.Add($num)
            continue
        }
        
        # Check if this line is a continuation (starts lowercase/with punctuation after break)
        # and the previous line in processed is a verse line that got cut off
        if ($processed.Count -gt 0) {
            $prev = $processed[$processed.Count - 1]
            $prevTrimmed = $prev.Trim()
            
            # If previous line is '(' or similar single-char and this is continuation
            if ($prevTrimmed -match '^[\(\[]$' -and $trimmed -match '^[\)\]n]') {
                # Join: remove the last line and concatenate
                $processed.RemoveAt($processed.Count - 1)
                $processed.Add($prevTrimmed + $trimmed)
                continue
            }
            
            # If previous line ends with partial word (no space before) and this starts lowercase
            if ($prevTrimmed -match '[\(\[]' -and $prevTrimmed -notmatch '[\)\]]' -and $trimmed -match '^[nkmn]\w') {
                $processed.RemoveAt($processed.Count - 1)
                $processed.Add($prevTrimmed + $trimmed)
                continue
            }
        }
        
        $processed.Add($trimmed)
    }
    
    # ---- PASS 3: Structure detection and formatting ----
    $outLines = [System.Collections.Generic.List[string]]::new()
    $state = "start"
    $proseBuffer = [System.Collections.Generic.List[string]]::new()
    $verseBuffer = [System.Collections.Generic.List[string]]::new()
    $currentStanzaNum = ""
    
    function Flush-Verse {
        if ($verseBuffer.Count -gt 0 -or $currentStanzaNum -ne "") {
            $joined = ($verseBuffer | ForEach-Object { $_.Trim() }) -join " "
            $joined = $joined -replace '\s+', ' '
            $joined = $joined -replace ' \|', '|'
            $joined = $joined -replace '\| ', '|'
            
            if ($currentStanzaNum -ne "" -or $joined -ne "") {
                if ($currentStanzaNum -ne "") {
                    $outLines.Add("")
                    $outLines.Add("### $currentStanzaNum")
                    $currentStanzaNum = ""
                }
                if ($joined -ne "") {
                    $outLines.Add($joined)
                    $outLines.Add("")
                }
            }
            $verseBuffer.Clear()
        }
    }
    
    function Flush-Prose {
        if ($proseBuffer.Count -gt 0) {
            $joined = ($proseBuffer | ForEach-Object { $_.Trim() }) -join " "
            $joined = $joined -replace '\s+', ' '
            if ($joined -ne "") {
                $outLines.Add($joined)
                $outLines.Add("")
            }
            $proseBuffer.Clear()
        }
    }
    
    foreach ($trimmed in $processed) {
        if ($trimmed -eq "") { continue }
        
        # Volume title
        if ($trimmed -match '^SÊRAT CÊNTHINI\s+') {
            Flush-Verse; Flush-Prose
            $outLines.Add("# $trimmed")
            $outLines.Add("")
            continue
        }
        
        # Pupuh header
        if ($trimmed -match '^[A-Z]+\s+Pupuh') {
            Flush-Verse; Flush-Prose
            $outLines.Add("## $trimmed")
            $outLines.Add("")
            continue
        }
        
        # Meter name
        if ($trimmed -match $meterPattern) {
            Flush-Verse; Flush-Prose
            $outLines.Add("## $trimmed")
            $outLines.Add("")
            continue
        }
        
        # Stanza number (standalone, must have period)
        if ($trimmed -match '^\d+\.$') {
            # Check if next line has pipe for stanza number detection
            # Since we already pre-processed, just check context
            Flush-Verse; Flush-Prose
            $currentStanzaNum = $trimmed
            continue
        }
        
        # Also handle stanza number without period if it's clearly a stanza marker
        # (appears between verse stanzas)
        if ($trimmed -match '^\d+$' -and $state -eq "verse") {
            # Could be a stanza number without period (like "691" in centhini12)
            if ($verseBuffer.Count -gt 0) {
                Flush-Verse
                $currentStanzaNum = $trimmed
                continue
            }
        }
        
        # Verse content
        if ($trimmed -match '\|') {
            if ($state -ne "verse") { Flush-Prose; $state = "verse" }
            
            # Check if line starts with a stanza number (e.g., "2. Sarusaking...")
            if ($trimmed -match '^(\d+\.)\s+(.*)') {
                $num = $matches[1]
                $rest = $matches[2].Trim()
                if ($rest -match '\|') {  # Only if there's pipe content
                    Flush-Verse
                    $currentStanzaNum = $num
                    $verseBuffer.Add($rest)
                    $state = "verse"
                    continue
                }
            }
            
            $verseBuffer.Add($trimmed)
            $state = "verse"
            continue
        }
        
        # Prose
        if ($state -eq "verse") { Flush-Verse; $state = "prose" }
        $proseBuffer.Add($trimmed)
        $state = "prose"
    }
    
    Flush-Verse
    Flush-Prose
    
    # ---- Clean up blank lines ----
    $cleaned = [System.Collections.Generic.List[string]]::new()
    $prevBlank = $false
    foreach ($l in $outLines) {
        if ($l.Trim() -eq "") {
            if (-not $prevBlank) { $cleaned.Add($l); $prevBlank = $true }
        } else {
            $cleaned.Add($l); $prevBlank = $false
        }
    }
    while ($cleaned.Count -gt 0 -and $cleaned[0].Trim() -eq "") { $cleaned.RemoveAt(0) }
    while ($cleaned.Count -gt 0 -and $cleaned[$cleaned.Count-1].Trim() -eq "") { $cleaned.RemoveAt($cleaned.Count-1) }
    
    $outputPath = Join-Path $OutputDir "$($file.BaseName).md"
    $cleaned | Set-Content $outputPath -Encoding UTF8
    Write-Host " done -> $($cleaned.Count) lines -> $outputPath"
}
