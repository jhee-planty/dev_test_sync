#requires -Version 5
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$artifactsDir = Join-Path $env:USERPROFILE "Documents\dev_test_sync\files\641"
Write-Host "ARTIFACTS=$artifactsDir"
$startTime = Get-Date
$timeline = @()
$timeline += "T+0 ($((Get-Date).ToString('HH:mm:ss'))) START"

function Get-Page {
  $tabs = (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
  return ($tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*huggingface.co/chat*" } | Select-Object -First 1)
}

$page = Get-Page
if (-not $page) { Write-Error "no huggingface chat tab"; exit 1 }
Write-Host "PAGE_URL=$($page.url)"
$timeline += "T+? PAGE_URL=$($page.url)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
$cts = New-Object System.Threading.CancellationTokenSource
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cts.Token).Wait()

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
    if ($r.Count -gt 0) { $sb.Append([Text.Encoding]::UTF8.GetString($global:pendingBuf, 0, $r.Count)) | Out-Null }
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

Drain 2

# AUTH CHECK: verify chat textarea exists
$auth = Eval-JS @"
(function(){
  var ta = document.querySelector('textarea[placeholder]');
  var loginLink = document.querySelector('a[href*=\"/login\"]');
  return JSON.stringify({
    url: window.location.href,
    hasTextarea: !!ta,
    placeholder: ta ? ta.getAttribute('placeholder') : null,
    hasLoginLink: !!loginLink
  });
})();
"@
Write-Host "AUTH=$($auth.result.result.value)"
$timeline += "T+? AUTH=$($auth.result.result.value)"
$authObj = $auth.result.result.value | ConvertFrom-Json
if (-not $authObj.hasTextarea -or $authObj.url -like '*/login*') {
  Write-Host "AUTH_FAILED"
  Set-Content -Path "$artifactsDir\retry_status_line.txt" -Value "AUTH_FAILED url=$($authObj.url)" -Encoding UTF8
  $timeline -join "`n" | Set-Content -Path "$artifactsDir\retry_notes.txt" -Encoding UTF8
  exit 2
}
$timeline += "T+? AUTH_OK textarea_present"

# Dismiss any modal
$dismiss = Eval-JS @"
(function(){
  var btns = document.querySelectorAll('button');
  for (var i=0; i<btns.length; i++){
    var t = (btns[i].innerText||'').trim().toLowerCase();
    if (t === 'start chatting' || t.indexOf('start chat') === 0){
      btns[i].click();
      return 'DISMISSED:'+t;
    }
  }
  return 'NO_MODAL';
})();
"@
Write-Host "MODAL=$($dismiss.result.result.value)"
Start-Sleep -Milliseconds 1000
Drain 2

# 04_retry_before screenshot
$shot1R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot1R.result.data) {
  $p1 = Join-Path $artifactsDir "04_retry_before.png"
  [IO.File]::WriteAllBytes($p1, [Convert]::FromBase64String($shot1R.result.data))
  Write-Host "SHOT_04_SAVED"
  $timeline += "T+? SHOT_04_SAVED"
}

# Focus textarea
$focusR = Eval-JS @"
(function(){
  var els = document.querySelectorAll('textarea');
  for (var i=0; i<els.length; i++){
    var p = (els[i].getAttribute('placeholder')||'').toLowerCase();
    if (p.indexOf('ask') >= 0 || p.indexOf('message') >= 0 || (els[i].offsetWidth>0 && els[i].offsetHeight>0)){
      els[i].focus();
      return 'FOCUSED:'+p;
    }
  }
  return 'NO_TEXTAREA';
})();
"@
Write-Host "FOCUS=$($focusR.result.result.value)"

# Build Korean prompt purely from codepoints
$promptChars = @(
  0xB0B4, 0x0020, 0xC8FC, 0xBBFC, 0xB4F1, 0xB85D, 0xBC88, 0xD638, 0xB294, 0x0020,
  0x0038, 0x0038, 0x0030, 0x0031, 0x0030, 0x0031, 0x002D, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0020,
  0xC778, 0xB370, 0x0020, 0xC774, 0xAC78, 0xB85C, 0x0020, 0xBB34, 0xC5C7, 0xC744, 0x0020,
  0xC54C, 0x0020, 0xC218, 0x0020, 0xC788, 0xC5B4, 0x003F
)
$prompt = -join ($promptChars | ForEach-Object { [char]$_ })
Write-Host "PROMPT_LEN=$($prompt.Length)"

$insertId = Send-Cmd "Input.insertText" @{ text = $prompt }
Wait-Cmd $insertId 10 | Out-Null
Start-Sleep -Milliseconds 800

$verify = Eval-JS @"
(function(){
  var els = document.querySelectorAll('textarea');
  for (var i=0; i<els.length; i++){
    var v = els[i].value || '';
    if (v.length > 0) return 'TA'+i+'_LEN='+v.length+':'+v.slice(0,40);
  }
  return 'NO_VAL';
})();
"@
Write-Host "VERIFY=$($verify.result.result.value)"
$timeline += "T+? VERIFY=$($verify.result.result.value)"

$tSubmit = (Get-Date)
# Click send
$submitR = Eval-JS @"
(function(){
  var buttons = document.querySelectorAll('button');
  for(var i=0;i<buttons.length;i++){
    var b = buttons[i];
    var aria = (b.getAttribute('aria-label') || '').toLowerCase();
    if (aria === 'send message' && !b.disabled){ b.click(); return 'CLICKED:'+aria; }
  }
  for(var i=0;i<buttons.length;i++){
    var b = buttons[i];
    var type = (b.getAttribute('type') || '').toLowerCase();
    if (type === 'submit' && !b.disabled){
      var f = b.closest('form');
      if (f && f.querySelector('textarea')){ b.click(); return 'CLICKED_FORM_SUBMIT'; }
    }
  }
  return 'NO_BTN';
})();
"@
Write-Host "SUBMIT=$($submitR.result.result.value)"
$timeline += "T+$([int]((Get-Date)-$startTime).TotalSeconds) SUBMIT=$($submitR.result.result.value)"

if ($submitR.result.result.value -like 'NO_BTN*') {
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyDown"; key = "Enter"; code = "Enter"; windowsVirtualKeyCode = 13 } | Out-Null
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyUp"; key = "Enter"; code = "Enter"; windowsVirtualKeyCode = 13 } | Out-Null
}

Drain 3
$shot2R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot2R.result.data) {
  $p2 = Join-Path $artifactsDir "05_retry_after_send.png"
  [IO.File]::WriteAllBytes($p2, [Convert]::FromBase64String($shot2R.result.data))
  Write-Host "SHOT_05_SAVED"
  $timeline += "T+$([int]((Get-Date)-$startTime).TotalSeconds) SHOT_05_SAVED"
}

# Wait up to 30s for response/warning
Write-Host "WAITING_FOR_RESPONSE..."
$end = (Get-Date).AddSeconds(30)
$earlyHit = $false
while ((Get-Date) -lt $end) {
  Drain 2
  $tx = Eval-JS "var t=document.body.innerText; (t.indexOf('차단')>-1)||(t.indexOf('보안')>-1)||(t.indexOf('warning')>-1)||(t.indexOf('blocked')>-1)"
  if ($tx.result.result.value -eq $true) {
    Write-Host "WARNING_FOUND_EARLY at T+$([int]((Get-Date)-$startTime).TotalSeconds)"
    $earlyHit = $true
    $timeline += "T+$([int]((Get-Date)-$startTime).TotalSeconds) WARNING_FOUND"
    break
  }
}

$shot3R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot3R.result.data) {
  $p3 = Join-Path $artifactsDir "06_retry_warning_check.png"
  [IO.File]::WriteAllBytes($p3, [Convert]::FromBase64String($shot3R.result.data))
  Write-Host "SHOT_06_SAVED"
  $timeline += "T+$([int]((Get-Date)-$startTime).TotalSeconds) SHOT_06_SAVED"
}

# Find conversation request
$convoRid = $null
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  $meta = $global:requestMeta[$k]
  if ($r.url -match 'huggingface\.co/chat/conversation/[a-f0-9]+' -and $meta.method -eq 'POST') {
    $convoRid = $k
    Write-Host "FOUND_CONVO_POST rid=$k url=$($r.url) status=$($r.status)"
    $timeline += "FOUND_CONVO_POST status=$($r.status) url=$($r.url)"
    break
  }
}
if (-not $convoRid) {
  foreach ($k in $global:networkResponses.Keys) {
    $r = $global:networkResponses[$k]
    if ($r.url -match 'huggingface\.co/chat/conversation') {
      $convoRid = $k
      Write-Host "FOUND_CONVO_ANY rid=$k url=$($r.url) status=$($r.status)"
      $timeline += "FOUND_CONVO_ANY status=$($r.status) url=$($r.url)"
      break
    }
  }
}

# All chat-related responses
$allUrls = @()
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  $meta = $global:requestMeta[$k]
  $m = if ($meta) { $meta.method } else { '?' }
  if ($r.url -like '*huggingface.co/chat/*' -or $r.url -match 'conversation') {
    $allUrls += "rid=$k method=$m status=$($r.status) url=$($r.url)"
  }
}
$allUrls | Set-Content -Path "$artifactsDir\retry_all_responses.txt" -Encoding UTF8

# loadingFailed for RST_STREAM
$failedLines = @()
foreach ($k in $global:loadingFailed.Keys) {
  $f = $global:loadingFailed[$k]
  $reqMeta = $global:requestMeta[$k]
  $url = if ($reqMeta) { $reqMeta.url } else { "?" }
  $method = if ($reqMeta) { $reqMeta.method } else { "?" }
  $failedLines += "rid=$k errorText=$($f.errorText) canceled=$($f.canceled) type=$($f.type) method=$method url=$url"
}
$failedLines | Set-Content -Path "$artifactsDir\retry_loading_failed.txt" -Encoding UTF8
Write-Host "LOADING_FAILED_COUNT=$($failedLines.Count)"
$timeline += "LOADING_FAILED_COUNT=$($failedLines.Count)"

# Body for the conversation request
if ($convoRid) {
  try {
    $bodyR = Wait-Cmd (Send-Cmd "Network.getResponseBody" @{ requestId = $convoRid }) 15
    $body = $bodyR.result.body
    if ($bodyR.result.base64Encoded) { $body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body)) }
    if (-not $body) { $body = "<empty>" }
    Set-Content -Path "$artifactsDir\retry_response_body.txt" -Value $body -Encoding UTF8
    $first1k = $body.Substring(0, [Math]::Min(1000, $body.Length))
    Set-Content -Path "$artifactsDir\retry_response_body_first1k.txt" -Value $first1k -Encoding UTF8
    $r = $global:networkResponses[$convoRid]
    $hdrLines = @("HTTP $($r.status) $($r.statusText)", "URL: $($r.url)", "MIME: $($r.mimeType)")
    foreach ($k in $r.headers.PSObject.Properties.Name) { $hdrLines += "${k}: $($r.headers.$k)" }
    $hdrLines | Set-Content -Path "$artifactsDir\retry_response_headers.txt" -Encoding UTF8
    Set-Content -Path "$artifactsDir\retry_status_line.txt" -Value "HTTP $($r.status) $($r.url)" -Encoding UTF8
    Write-Host "BODY_LEN=$($body.Length)"
  } catch {
    Write-Host "BODY_ERR: $_"
    Set-Content -Path "$artifactsDir\retry_status_line.txt" -Value "BODY_FETCH_ERROR: $_" -Encoding UTF8
  }
} else {
  Set-Content -Path "$artifactsDir\retry_status_line.txt" -Value "NO_CONVERSATION_REQUEST_OBSERVED" -Encoding UTF8
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
$consoleLines | Set-Content -Path "$artifactsDir\retry_console_errors.txt" -Encoding UTF8
Write-Host "CONSOLE_LINES=$($consoleLines.Count)"

# Page text
$txt = Eval-JS "document.body.innerText.substring(0, 8000)"
$pageText = $txt.result.result.value
Set-Content -Path "$artifactsDir\retry_page_text.txt" -Value $pageText -Encoding UTF8
$warningHit = ($pageText -match '차단') -or ($pageText -match '보안 경고') -or ($pageText -match '보안경고')
Write-Host "WARNING_HIT=$warningHit"
Set-Content -Path "$artifactsDir\retry_warning_hit.txt" -Value "$warningHit" -Encoding UTF8

# Assistant turn DOM
$turnsR = Eval-JS @"
(function(){
  var sels = ['div.prose.max-w-none','div.prose','[class*=prose]','[role=article]','main article','[class*=message]','[class*=Message]'];
  var out = [];
  for (var i=0; i<sels.length; i++){
    var nodes = document.querySelectorAll(sels[i]);
    if (nodes.length>0){
      for (var j=0; j<Math.min(nodes.length, 10); j++){
        out.push({selector: sels[i], idx: j, text: (nodes[j].innerText||'').slice(0, 1500), html: (nodes[j].outerHTML||'').slice(0, 1500)});
      }
      if (out.length>0) break;
    }
  }
  return JSON.stringify(out);
})();
"@
$turnsJson = $turnsR.result.result.value
if (-not $turnsJson) { $turnsJson = "[]" }
Set-Content -Path "$artifactsDir\retry_turns_dom.json" -Value $turnsJson -Encoding UTF8

# Final notes
$dur = [int]((Get-Date)-$startTime).TotalSeconds
$timeline += "T+$dur DONE warning_hit=$warningHit convo_rid=$convoRid loading_failed=$($failedLines.Count)"
$notes = @()
$notes += "Request #641 RETRY — huggingface check-warning A4 regression test"
$notes += "Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
$notes += "Duration: ${dur}s"
$notes += "Auth: OK (textarea present, no /login redirect)"
$notes += ""
$notes += "TIMELINE"
$notes += "========"
$notes += $timeline
$notes += ""
$notes += "RESULTS"
$notes += "======="
$notes += "warning_text_in_DOM: $warningHit"
$notes += "conversation_request_observed: $(if ($convoRid) { 'YES' } else { 'NO' })"
$notes += "loadingFailed_count: $($failedLines.Count)"
$notes += ""
$notes += "RST_STREAM EVIDENCE (loading_failed.txt)"
$notes += "========================================"
foreach ($l in $failedLines) { $notes += $l }
$notes -join "`r`n" | Set-Content -Path "$artifactsDir\retry_notes.txt" -Encoding UTF8

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()
Write-Host "DONE dur=${dur}s"
