$ErrorActionPreference = 'Stop'
$path = 'd:\test\index.html'
$content = Get-Content -Path $path -Raw
$downloadDir = 'd:\test\images\downloaded'
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

$urlMap = @{}

function Add-Url([string]$u) {
  if ([string]::IsNullOrWhiteSpace($u)) { return }
  if ($u -match '^https?://[^\s"'']+\.(?:png|jpe?g|webp|gif|svg|avif|bmp)(?:\?[^\s"'']*)?$') {
    if (-not $urlMap.ContainsKey($u)) { $urlMap[$u] = $null }
  }
}

$attrPattern = '(?:src|data-src|poster)\s*=\s*(["''])(https?://[^"'']+)\1'
[regex]::Matches($content, $attrPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object {
  Add-Url $_.Groups[2].Value
}

$srcsetPattern = '(?:srcset|data-srcset)\s*=\s*(["''])([^"'']+)\1'
[regex]::Matches($content, $srcsetPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object {
  $srcset = $_.Groups[2].Value
  $parts = $srcset -split ','
  foreach ($part in $parts) {
    $chunk = $part.Trim()
    if (-not $chunk) { continue }
    $url = ($chunk -split '\s+')[0]
    Add-Url $url
  }
}

$counter = 0
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(30)
$sha1 = [Security.Cryptography.SHA1]::Create()

foreach ($url in @($urlMap.Keys)) {
  try {
    $uri = [Uri]$url
    $ext = [System.IO.Path]::GetExtension($uri.AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.jpg' }
    $hashBytes = $sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($url))
    $hash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
    $name = "img_$hash$ext"
    $target = Join-Path $downloadDir $name

    if (-not (Test-Path $target)) {
      $bytes = $client.GetByteArrayAsync($url).GetAwaiter().GetResult()
      [System.IO.File]::WriteAllBytes($target, $bytes)
      $counter++
    }

    $urlMap[$url] = "images/downloaded/$name"
  }
  catch {
    Write-Host "SKIP: $url"
    $urlMap[$url] = $null
  }
}

foreach ($k in @($urlMap.Keys)) {
  $v = $urlMap[$k]
  if ($v) { $content = $content.Replace($k, $v) }
}

Set-Content -Path $path -Value $content -Encoding UTF8

Write-Host "Downloaded: $counter"
Write-Host "Mapped: $($urlMap.Keys.Count)"
