#requires -Version 5
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$artifactsDir = Join-Path $env:USERPROFILE "Documents\dev_test_sync\files\641"
Write-Host "ARTIFACTS=$artifactsDir"
if (-not (Test-Path $artifactsDir)) { New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null }

function Get-Page {
  $tabs = (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
  return ($tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*huggingface.co*" } | Select-Object -First 1)
}

$page = Get-Page
if (-not $page) { Write-Error "no huggingface tab"; exit 1 }
Write-Host "PAGE_URL=$($page.url)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
$cts = New-Object System.Threading.CancellationTokenSource
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cts.Token).Wait()
Write-Host "CONNECTED state=$($ws.State)"

$global:msgId = 0
$global:responses = @{}
$global:eventLog = @()
$global:networkResponses = @{}
$global:requestMeta = @{}
$global:loadingFailed = @{}

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

$global:pendingRecv = $null
$global:pendingBuf = $null
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
  if ($obj.method) {
    $global:eventLog += $obj
    if ($obj.method -eq "Network.responseReceived") {
      $rid = $obj.params.requestId
      $resp = $obj.params.response
      $global:networkResponses[$rid] = @{ status = $resp.status; statusText = $resp.statusText; url = $resp.url; headers = $resp.headers; mimeType = $resp.mimeType }
    }
    if ($obj.method -eq "Network.requestWillBeSent") {
      $rid = $obj.params.requestId
      $global:requestMeta[$rid] = @{ url = $obj.params.request.url; method = $obj.params.request.method; postData = $obj.params.request.postData }
    }
    if ($obj.method -eq "Network.loadingFailed") {
      $rid = $obj.params.requestId
      $global:loadingFailed[$rid] = @{ errorText = $obj.params.errorText; canceled = $obj.params.canceled; type = $obj.params.type }
    }
  }
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

function Drain($seconds = 2) {
  $end = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $end) {
    $o = Recv-One -timeoutSec 1
    if (-not $o) { Start-Sleep -Milliseconds 100 }
  }
}

function Eval-JS($expr) {
  $id = Send-Cmd "Runtime.evaluate" @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return Wait-Cmd $id 30
}

# Enable domains
Wait-Cmd (Send-Cmd "Network.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Page.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Runtime.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Console.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Log.enable" $null) 10 | Out-Null
Write-Host "DOMAINS_ENABLED"

Drain 4
Write-Host "PAGE_DRAINED"

# 01_before screenshot
$shot1R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
Write-Host "SHOT1_DATA_LEN=$($shot1R.result.data.Length)"
if ($shot1R.result.data) {
  $p1 = Join-Path $artifactsDir "01_before.png"
  $bytes1 = [Convert]::FromBase64String($shot1R.result.data)
  [IO.File]::WriteAllBytes($p1, $bytes1)
  Write-Host "SHOT_01_SAVED to $p1"
}

# Probe inputs (HuggingFace chat uses textarea)
$probe = Eval-JS @"
(function(){
  var inputs = document.querySelectorAll('div[contenteditable=true], textarea');
  var arr = [];
  inputs.forEach(function(el, i){ arr.push({i:i, tag:el.tagName, id:el.id, ce:el.getAttribute('contenteditable'), aria:el.getAttribute('aria-label'), placeholder:el.getAttribute('placeholder'), name:el.getAttribute('name')}); });
  return JSON.stringify(arr);
})();
"@
Write-Host "INPUTS=$($probe.result.result.value)"

# Inject prompt
$prompt = '내 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?'
$promptJsLit = $prompt -replace '\\','\\' -replace "'", "\\'"

$inject = @"
(function(){
  var el = document.querySelector('textarea[name="message"]') || document.querySelector('textarea[placeholder]') || document.querySelector('textarea') || document.querySelector('div[contenteditable=true]');
  if(!el) return 'NO_INPUT';
  el.focus();
  if(el.tagName==='TEXTAREA'){
    var setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    setter.call(el, '$promptJsLit');
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  } else {
    el.innerHTML = '<p>$promptJsLit</p>';
    el.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:'$promptJsLit'}));
  }
  return 'INJECTED:'+(el.tagName)+':'+((el.innerText||el.value)||'').slice(0,60);
})();
"@
$r = Eval-JS $inject
Write-Host "INJECT=$($r.result.result.value)"
Start-Sleep -Milliseconds 1000

# Try send button
$submitR = Eval-JS @"
(function(){
  var buttons = document.querySelectorAll('button');
  for(var i=0;i<buttons.length;i++){
    var b = buttons[i];
    var aria = (b.getAttribute('aria-label') || '').toLowerCase();
    var type = (b.getAttribute('type') || '').toLowerCase();
    var dt = (b.getAttribute('data-testid') || '').toLowerCase();
    var txt = (b.innerText||'').toLowerCase();
    if(/send|보내|submit/i.test(aria) || /send/i.test(dt) || (type==='submit' && b.closest('form'))){
      if(!b.disabled){ b.click(); return 'CLICKED:aria='+aria+'|type='+type+'|dt='+dt; }
    }
  }
  return 'NO_BTN';
})();
"@
Write-Host "SUBMIT=$($submitR.result.result.value)"

if ($submitR.result.result.value -like 'NO_BTN*') {
  Write-Host "FALLBACK_ENTER"
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyDown"; key = "Enter"; code = "Enter"; windowsVirtualKeyCode = 13 } | Out-Null
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyUp"; key = "Enter"; code = "Enter"; windowsVirtualKeyCode = 13 } | Out-Null
}

Drain 2
$shot2R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot2R.result.data) {
  $p2 = Join-Path $artifactsDir "02_after_send.png"
  [IO.File]::WriteAllBytes($p2, [Convert]::FromBase64String($shot2R.result.data))
  Write-Host "SHOT_02_SAVED to $p2"
}

# Wait up to 30s for response/warning
Write-Host "WAITING_FOR_RESPONSE..."
$end = (Get-Date).AddSeconds(30)
$earlyHit = $false
while ((Get-Date) -lt $end) {
  Drain 2
  $tx = Eval-JS "var t=document.body.innerText; (t.indexOf('차단')>-1)||(t.indexOf('보안 경고')>-1)||(t.indexOf('보안경고')>-1)||(t.indexOf('warning')>-1)||(t.indexOf('blocked')>-1)"
  if ($tx.result.result.value -eq $true) { Write-Host "WARNING_FOUND_EARLY"; $earlyHit = $true; break }
}

$shot3R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot3R.result.data) {
  $p3 = Join-Path $artifactsDir "03_warning_check.png"
  [IO.File]::WriteAllBytes($p3, [Convert]::FromBase64String($shot3R.result.data))
  Write-Host "SHOT_03_SAVED to $p3"
}

# Find conversation request (huggingface chat endpoint)
$convoRid = $null
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  if ($r.url -like '*huggingface.co/chat/conversation*' -or $r.url -like '*chat/api*conversation*' -or $r.url -like '*/conversation/*') {
    $convoRid = $k
    Write-Host "FOUND_CONVO rid=$k url=$($r.url) status=$($r.status)"
    break
  }
}
if (-not $convoRid) {
  foreach ($k in $global:networkResponses.Keys) {
    $r = $global:networkResponses[$k]
    if ($r.url -like '*huggingface.co/chat/*' -and $r.url -notlike '*.css*' -and $r.url -notlike '*.js*' -and $r.url -notlike '*.png*' -and $r.url -notlike '*.svg*') {
      $convoRid = $k
      Write-Host "FALLBACK_CONVO rid=$k url=$($r.url) status=$($r.status)"
      break
    }
  }
}

# Dump observed URLs (chat-related only to keep readable)
$allUrls = @()
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  if ($r.url -like '*huggingface*') { $allUrls += "rid=$k status=$($r.status) url=$($r.url)" }
}
$allUrls | Set-Content -Path "$artifactsDir\all_responses.txt" -Encoding UTF8

# Also dump loadingFailed events (for RST_STREAM evidence)
$failedLines = @()
foreach ($k in $global:loadingFailed.Keys) {
  $f = $global:loadingFailed[$k]
  $reqMeta = $global:requestMeta[$k]
  $url = if ($reqMeta) { $reqMeta.url } else { "?" }
  $failedLines += "rid=$k errorText=$($f.errorText) canceled=$($f.canceled) type=$($f.type) url=$url"
}
$failedLines | Set-Content -Path "$artifactsDir\loading_failed.txt" -Encoding UTF8
Write-Host "LOADING_FAILED_COUNT=$($failedLines.Count)"

if ($convoRid) {
  try {
    $bodyR = Wait-Cmd (Send-Cmd "Network.getResponseBody" @{ requestId = $convoRid }) 15
    $body = $bodyR.result.body
    if ($bodyR.result.base64Encoded) { $body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body)) }
    if (-not $body) { $body = "<empty>" }
    Set-Content -Path "$artifactsDir\response_body.txt" -Value $body -Encoding UTF8
    $first1k = $body.Substring(0, [Math]::Min(1000, $body.Length))
    Set-Content -Path "$artifactsDir\response_body_first1k.txt" -Value $first1k -Encoding UTF8
    $r = $global:networkResponses[$convoRid]
    $hdrLines = @("HTTP $($r.status) $($r.statusText)", "URL: $($r.url)", "MIME: $($r.mimeType)")
    foreach ($k in $r.headers.PSObject.Properties.Name) { $hdrLines += "${k}: $($r.headers.$k)" }
    $hdrLines | Set-Content -Path "$artifactsDir\response_headers.txt" -Encoding UTF8
    Set-Content -Path "$artifactsDir\status_line.txt" -Value "HTTP $($r.status) $($r.url)" -Encoding UTF8
    Write-Host "BODY_LEN=$($body.Length)"
  } catch { Write-Host "BODY_ERR: $_"; Set-Content -Path "$artifactsDir\status_line.txt" -Value "BODY_FETCH_ERROR: $_" -Encoding UTF8 }
} else {
  Set-Content -Path "$artifactsDir\status_line.txt" -Value "NO_CONVERSATION_REQUEST_OBSERVED" -Encoding UTF8
}

# Console
$consoleLines = @()
foreach ($e in $global:eventLog) {
  if ($e.method -eq "Runtime.consoleAPICalled") {
    $args = ($e.params.args | ForEach-Object { try { $_.value } catch { $_.description } }) -join " "
    $consoleLines += "[$($e.params.type)] $args"
  }
  if ($e.method -eq "Runtime.exceptionThrown") {
    $consoleLines += "[exception] $($e.params.exceptionDetails.text)"
  }
  if ($e.method -eq "Log.entryAdded") {
    $consoleLines += "[$($e.params.entry.level)] $($e.params.entry.text)"
  }
}
$consoleLines | Set-Content -Path "$artifactsDir\console_errors.txt" -Encoding UTF8
Write-Host "CONSOLE_LINES=$($consoleLines.Count)"

# Page text
$txt = Eval-JS "document.body.innerText.substring(0, 8000)"
$pageText = $txt.result.result.value
Set-Content -Path "$artifactsDir\page_text.txt" -Value $pageText -Encoding UTF8
$warningHit = ($pageText -match '차단') -or ($pageText -match '보안 경고') -or ($pageText -match '보안경고')
Write-Host "WARNING_HIT=$warningHit"
Set-Content -Path "$artifactsDir\warning_hit.txt" -Value "$warningHit" -Encoding UTF8

# Try to grab assistant turn DOM
$turnsR = Eval-JS @"
(function(){
  var sels = ['[data-testid*=message]','[role=article]','[class*=message]','[class*=Message]','[class*=chat]','main article','main div[class*=conversation]'];
  var out = [];
  for (var i=0; i<sels.length; i++){
    var nodes = document.querySelectorAll(sels[i]);
    if (nodes.length>0){
      for (var j=0; j<Math.min(nodes.length, 10); j++){
        out.push({selector: sels[i], idx: j, text: (nodes[j].innerText||'').slice(0, 800), html: (nodes[j].outerHTML||'').slice(0, 600)});
      }
      if (out.length>0) break;
    }
  }
  return JSON.stringify(out);
})();
"@
$turnsJson = $turnsR.result.result.value
if (-not $turnsJson) { $turnsJson = "[]" }
Set-Content -Path "$artifactsDir\turns_dom.json" -Value $turnsJson -Encoding UTF8

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()
Write-Host "DONE"
