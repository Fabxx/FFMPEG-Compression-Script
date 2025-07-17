Add-Type -AssemblyName System.Windows.Forms

# Selezione cartella
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the folder containing the videos"

if ($folderBrowser.ShowDialog() -ne "OK") {
    Write-Host "No folder selected. Exiting."
    exit
}

$path = $folderBrowser.SelectedPath
Set-Location $path

# Crea cartella output
$outDir = Join-Path $path "out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# CPU info
$threads = [Environment]::ProcessorCount
$lscpu = & wmic cpu get NumberOfCores /value
$physicalCores = ($lscpu -split "=")[1] -as [int]

# Itera i file
Get-ChildItem -File -LiteralPath $path | ForEach-Object {
    $file = $_.FullName
    $filenameNoExt = $_.BaseName
    $extension = $_.Extension.TrimStart('.')

    if ($extension -eq "webm") {
        Write-Host "Skipping $($_.Name) (already .webm)"
        return
    }

    $segmentPattern = Join-Path $path ("{0}_%04d.{1}" -f $filenameNoExt, $extension)

    Start-Process -FilePath "ffmpeg" -ArgumentList @(
        "-hide_banner",
        "-loglevel", "error",
        "-i", "`"$file`"",
        "-c", "copy",
        "-f", "segment",
        "-segment_time", "30",
        "-reset_timestamps", "1",
        "`"$segmentPattern`""
    ) -Wait -NoNewWindow

    $firstSegment = Join-Path $path ("{0}_0000.{1}" -f $filenameNoExt, $extension)
    if (-not (Test-Path -LiteralPath $firstSegment)) {
        Write-Host "Error: segmentation failed for $($_.Name)"
        return
    }

    # Prendi i segmenti
    $segmentFiles = Get-ChildItem -File -LiteralPath $path | Where-Object {
        $_.BaseName.StartsWith("$filenameNoExt" + "_") -and $_.Extension -eq ".$extension"
    }

    # Avvia conversioni in parallelo
    $jobs = @()
    foreach ($segmentFile in $segmentFiles) {
        $job = Start-ThreadJob -ScriptBlock {
            param($segment, $threads, $physicalCores)
            $webmOut = "$segment.webm"

            Start-Process -FilePath "ffmpeg" -ArgumentList @(
                "-hide_banner",
                "-loglevel", "error",
                "-i", "`"$segment`"",
                "-c:v", "libvpx-vp9",
                "-b:v", "0",
                "-crf", "40",
                "-c:a", "libopus",
                "-ac", "2",
                "-threads", "$threads",
                "-row-mt", "1",
                "-cpu-used", "$physicalCores",
                "-tile-columns", "4",
                "-frame-parallel", "1",
                "`"$webmOut`""
            ) -Wait -NoNewWindow
        } -ArgumentList $segmentFile.FullName, $threads, $physicalCores

        $jobs += $job
    }

    # Attendi fine conversioni
    $jobs | ForEach-Object { Receive-Job -Job $_ -Wait -AutoRemoveJob }

    # Lista per concat
    $webmFiles = Get-ChildItem -File -LiteralPath $path | Where-Object {
        $_.BaseName.StartsWith("$filenameNoExt" + "_") -and $_.Extension -eq ".webm"
    } | Sort-Object Name

    if ($webmFiles.Count -eq 0) {
        Write-Host "Errore: nessun file .webm generato. Skipping."
        return
    }

    $listPath = Join-Path $path "file_list.txt"
    if (Test-Path $listPath) { Remove-Item -LiteralPath $listPath -Force }

    foreach ($webm in $webmFiles) {
        # Escape backslash per ffmpeg
        $escapedPath = $webm.FullName -replace '\\', '\\\\'
        Add-Content -Path $listPath -Value "file '$escapedPath'" -Encoding utf8
    }

    # Concatenazione finale
    $outputWebm = Join-Path $outDir "$filenameNoExt.webm"
    Start-Process -FilePath "ffmpeg" -ArgumentList @(
        "-hide_banner",
        "-loglevel", "error",
        "-f", "concat",
        "-safe", "0",
        "-i", "`"$listPath`"",
        "-c", "copy",
        "`"$outputWebm`""
    ) -Wait -NoNewWindow

    # Pulizia
    $segmentFiles | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    $webmFiles    | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
    Remove-Item -LiteralPath $listPath -Force

    Write-Host "Processed $($file) -> $outputWebm"
}
