#requires -Version 5
$ErrorActionPreference = "Stop"
$artifactsDir = Join-Path $env:USERPROFILE "Documents\dev_test_sync\files\640"

$tabs = (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
$page = $tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*chatgpt.com*" } | Select-Object -First 1
if (-not $page) { Write-Error "no chatgpt tab"; exit 1 }
Write-Host "PAGE_URL=$($page.url)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cts.Token).Wait()

# Use page's fetch from console to retry the actual /conversation call... but we already missed it.
# Instead, query the rendered DOM for the warning bubble HTML directly.

$global:msgId = 0
$global:responses = @{}
$global:pendingRecv = $null
$global:pendingBuf = $null

function Send-Cmd($method, $params) {
  $global:msgId++
  $id = $global:msgId
  $obj = @{ id = $id; method = $method }
  if ($params) { $obj.params = $params }
  $json = $obj | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $seg = New-Object System.ArraySegment[byte] (,$bytes)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
  return $id
}

function Recv-One($timeoutSec = 1) {
  $sb = New-Object Text.StringBuilder
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  $first = $true
  do {
    if (-not $global:pendingRecv) {
      $global:pendingBuf = New-Object byte[] 65536
      $seg = New-Object System.ArraySegment[byte] (,$global:pendingBuf)
      $global:pendingRecv = $ws.ReceiveAsync($seg, $cts.Token)
    }
    while (-not $global:pendingRecv.IsCompleted) {
      if ((Get-Date) -gt $deadline) {
        if ($first) { return $null }
        $deadline = (Get-Date).AddSeconds(5)
      }
      Start-Sleep -Milliseconds 30
    }
    $r = $global:pendingRecv.Result
    $global:pendingRecv = $null
    if ($r.Count -gt 0) {
      $sb.Append([Text.Encoding]::UTF8.GetString($global:pendingBuf, 0, $r.Count)) | Out-Null
    }
    $first = $false
    if ($r.EndOfMessage) { break }
  } while ($true)
  $msg = $sb.ToString()
  if (-not $msg) { return $null }
  try { $obj = $msg | ConvertFrom-Json } catch { return $null }
  if ($obj.id) { $global:responses[$obj.id] = $obj }
  return $obj
}

function Wait-Cmd($id, $timeoutSec = 30) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    if ($global:responses.ContainsKey($id)) { return $global:responses[$id] }
    $o = Recv-One -timeoutSec 2
    if ($o -and $o.id -eq $id) { return $o }
  }
  return $null
}

function Eval-JS($expr) {
  $id = Send-Cmd "Runtime.evaluate" @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return Wait-Cmd $id 30
}

Wait-Cmd (Send-Cmd "Runtime.enable" $null) 10 | Out-Null

# Get the warning bubble HTML
$r = Eval-JS @"
(function(){
  // Find element containing the warning text
  var bodyText = document.body.innerText;
  var marker = '민감정보가 포함된 요청은 보안 정책에 의해 차단되었습니다';
  var idx = bodyText.indexOf(marker);
  if (idx === -1) return JSON.stringify({found:false, snippet:bodyText.substring(0,500)});
  // Walk DOM to find the element
  var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
  var node;
  while (node = walker.nextNode()) {
    if (node.nodeValue && node.nodeValue.indexOf('민감정보가 포함된') >= 0) {
      var el = node.parentElement;
      // climb up 3 levels for context
      for (var i = 0; i < 3 && el.parentElement; i++) el = el.parentElement;
      return JSON.stringify({
        found: true,
        marker_text: node.nodeValue,
        wrapper_tag: el.tagName,
        wrapper_class: el.className,
        wrapper_outer_html: el.outerHTML.substring(0, 2000),
        full_text: bodyText.substring(Math.max(0, idx-50), idx+300)
      });
    }
  }
  return JSON.stringify({found:false, reason:'walker_failed'});
})();
"@
$out = $r.result.result.value
Write-Host "RESULT_LEN=$($out.Length)"
Set-Content -Path (Join-Path $artifactsDir "warning_dom.json") -Value $out -Encoding UTF8

# Also dump the recent assistant turn HTML
$r2 = Eval-JS @"
(function(){
  var turns = document.querySelectorAll('[data-message-author-role=\"assistant\"], [data-message-author-role=\"user\"], article, [data-testid*=\"conversation-turn\"]');
  var info = [];
  for (var i = 0; i < turns.length; i++) {
    var t = turns[i];
    info.push({
      i: i,
      tag: t.tagName,
      role: t.getAttribute('data-message-author-role') || t.getAttribute('data-testid') || '',
      text: (t.innerText || '').substring(0, 300)
    });
  }
  return JSON.stringify(info);
})();
"@
Set-Content -Path (Join-Path $artifactsDir "turns_dom.json") -Value $r2.result.result.value -Encoding UTF8
Write-Host "TURNS_LEN=$($r2.result.result.value.Length)"

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()
Write-Host "DONE"
