#requires -Version 5
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$artifactsDir = Join-Path $env:USERPROFILE "Documents\dev_test_sync\files\641"
$startTime = Get-Date
$timeline = @()
$timeline += "T+0 ($((Get-Date).ToString('HH:mm:ss'))) START retry2 — no modal click"

function Get-Page {
  $tabs = (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
  # prefer /chat/ over /login
  $chatTab = $tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*huggingface.co/chat*" -and $_.url -notlike "*login*" } | Select-Object -First 1
  if ($chatTab) { return $chatTab }
  return ($tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*huggingface.co*" } | Select-Object -First 1)
}

# First navigate to /chat/
$page = Get-Page
if (-not $page) { Write-Error "no huggingface tab"; exit 1 }
Write-Host "INITIAL_PAGE_URL=$($page.url)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
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

Wait-Cmd (Send-Cmd "Network.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Page.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Runtime.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Console.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Log.enable" $null) 10 | Out-Null

# Force navigate to /chat/ (in case currently on /login)
$nav = Send-Cmd "Page.navigate" @{ url = "https://huggingface.co/chat/" }
Wait-Cmd $nav 10 | Out-Null
Start-Sleep -Seconds 4
Drain 3
$timeline += "T+? Navigated to /chat/"

# CHECK URL
$loc = Eval-JS "window.location.href"
$currentUrl = $loc.result.result.value
Write-Host "POST_NAV_URL=$currentUrl"
$timeline += "T+? POST_NAV_URL=$currentUrl"

# AUTH GATE: textarea must exist
$auth = Eval-JS @"
(function(){
  var ta = document.querySelector('textarea[placeholder]');
  return JSON.stringify({
    url: window.location.href,
    hasTextarea: !!ta,
    placeholder: ta ? ta.getAttribute('placeholder') : null,
    visible: ta ? (ta.offsetWidth>0 && ta.offsetHeight>0) : false
  });
})();
"@
Write-Host "AUTH=$($auth.result.result.value)"
$timeline += "T+? AUTH=$($auth.result.result.value)"
$authObj = $auth.result.result.value | ConvertFrom-Json
if (-not $authObj.hasTextarea -or $authObj.url -like '*/login*') {
  Write-Host "AUTH_FAILED no textarea or on /login"
  Set-Content -Path "$artifactsDir\retry_status_line.txt" -Value "AUTH_FAILED url=$($authObj.url)" -Encoding UTF8
  $shotF = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
  if ($shotF.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $artifactsDir "06_retry_warning_check.png"), [Convert]::FromBase64String($shotF.result.data))
  }
  $timeline -join "`r`n" | Set-Content -Path "$artifactsDir\retry_notes.txt" -Encoding UTF8
  exit 2
}

# 04_retry_before — DO NOT click "Start chatting" modal (that triggers OAuth)
$shot1R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot1R.result.data) {
  [IO.File]::WriteAllBytes((Join-Path $artifactsDir "04_retry_before.png"), [Convert]::FromBase64String($shot1R.result.data))
  Write-Host "SHOT_04_SAVED"
}

# Try to dismiss modal by ESC key (not by clicking 'Start chatting')
Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyDown"; key = "Escape"; code = "Escape"; windowsVirtualKeyCode = 27 } | Out-Null
Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyUp"; key = "Escape"; code = "Escape"; windowsVirtualKeyCode = 27 } | Out-Null
Start-Sleep -Milliseconds 500

# Focus textarea via JS
$focusR = Eval-JS @"
(function(){
  var els = document.querySelectorAll('textarea');
  for (var i=0; i<els.length; i++){
    var p = (els[i].getAttribute('placeholder')||'').toLowerCase();
    if (p.indexOf('ask') >= 0 || p.indexOf('message') >= 0){
      els[i].focus();
      els[i].click();
      return 'FOCUSED:i='+i+':p='+p+':visible='+(els[i].offsetWidth>0);
    }
  }
  return 'NO_TEXTAREA';
})();
"@
Write-Host "FOCUS=$($focusR.result.result.value)"
$timeline += "T+? FOCUS=$($focusR.result.result.value)"

# Korean prompt via codepoints
$promptChars = @(
  0xB0B4, 0x0020, 0xC8FC, 0xBBFC, 0xB4F1, 0xB85D, 0xBC88, 0xD638, 0xB294, 0x0020,
  0x0038, 0x0038, 0x0030, 0x0031, 0x0030, 0x0031, 0x002D, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0020,
  0xC778, 0xB370, 0x0020, 0xC774, 0xAC78, 0xB85C, 0x0020, 0xBB34, 0xC5C7, 0xC744, 0x0020,
  0xC54C, 0x0020, 0xC218, 0x0020, 0xC788, 0xC5B4, 0x003F
)
$prompt = -join ($promptChars | ForEach-Object { [char]$_ })

# Try CDP Input.insertText first
$insertId = Send-Cmd "Input.insertText" @{ text = $prompt }
Wait-Cmd $insertId 10 | Out-Null
Start-Sleep -Milliseconds 800

$verify = Eval-JS @"
(function(){
  var els = document.querySelectorAll('textarea');
  for (var i=0; i<els.length; i++){
    var v = els[i].value || '';
    if (v.length > 0) return 'TA'+i+'_LEN='+v.length;
  }
  return 'NO_VAL';
})();
"@
Write-Host "VERIFY1=$($verify.result.result.value)"

# If insertText didn't work (focus lost), try direct DOM injection
if ($verify.result.result.value -eq 'NO_VAL') {
  Write-Host "FALLBACK_DOM_SET"
  # Use Runtime.evaluate to set value via React-friendly setter
  $jsLines = @(
    "(function(){",
    "  var els = document.querySelectorAll('textarea');",
    "  var target = null;",
    "  for (var i=0; i<els.length; i++){",
    "    var p = (els[i].getAttribute('placeholder')||'').toLowerCase();",
    "    if (p.indexOf('ask') >= 0){ target = els[i]; break; }",
    "  }",
    "  if (!target && els.length>0) target = els[0];",
    "  if (!target) return 'NO_TARGET';",
    "  target.focus();",
    "  var setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;",
    "  var s = String.fromCodePoint(0xB0B4) + ' ' +",
    "    String.fromCodePoint(0xC8FC) + String.fromCodePoint(0xBBFC) + String.fromCodePoint(0xB4F1) + String.fromCodePoint(0xB85D) + String.fromCodePoint(0xBC88) + String.fromCodePoint(0xD638) + String.fromCodePoint(0xB294) + ' ' +",
    "    '880101-1234567 ' +",
    "    String.fromCodePoint(0xC778) + String.fromCodePoint(0xB370) + ' ' +",
    "    String.fromCodePoint(0xC774) + String.fromCodePoint(0xAC78) + String.fromCodePoint(0xB85C) + ' ' +",
    "    String.fromCodePoint(0xBB34) + String.fromCodePoint(0xC5C7) + String.fromCodePoint(0xC744) + ' ' +",
    "    String.fromCodePoint(0xC54C) + ' ' + String.fromCodePoint(0xC218) + ' ' + String.fromCodePoint(0xC788) + String.fromCodePoint(0xC5B4) + '?';",
    "  setter.call(target, s);",
    "  target.dispatchEvent(new Event('input', {bubbles:true}));",
    "  target.dispatchEvent(new Event('change', {bubbles:true}));",
    "  return 'INJECTED:'+target.value.length+':'+target.value.slice(0,30);",
    "})();"
  )
  $js = $jsLines -join "`n"
  $r = Eval-JS $js
  Write-Host "DOM_INJECT=$($r.result.result.value)"
  $timeline += "T+? DOM_INJECT=$($r.result.result.value)"
  Start-Sleep -Milliseconds 500
  $verify2 = Eval-JS @"
(function(){
  var els = document.querySelectorAll('textarea');
  for (var i=0; i<els.length; i++){
    var v = els[i].value || '';
    if (v.length > 0) return 'TA'+i+'_LEN='+v.length;
  }
  return 'NO_VAL';
})();
"@
  Write-Host "VERIFY2=$($verify2.result.result.value)"
  $timeline += "T+? VERIFY2=$($verify2.result.result.value)"
}

# Click send button
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
      if (f && f.querySelector('textarea')){ b.click(); return 'CLICKED_FORM_SUBMIT:i='+i; }
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
  [IO.File]::WriteAllBytes((Join-Path $artifactsDir "05_retry_after_send.png"), [Convert]::FromBase64String($shot2R.result.data))
  Write-Host "SHOT_05_SAVED"
}

Write-Host "WAITING_FOR_RESPONSE..."
$end = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $end) {
  Drain 2
  $tx = Eval-JS "var t=document.body.innerText; (t.indexOf('차단')>-1)||(t.indexOf('보안')>-1)||(t.indexOf('warning')>-1)||(t.indexOf('blocked')>-1)"
  if ($tx.result.result.value -eq $true) {
    Write-Host "WARNING_FOUND_EARLY at T+$([int]((Get-Date)-$startTime).TotalSeconds)"
    $timeline += "T+$([int]((Get-Date)-$startTime).TotalSeconds) WARNING_FOUND"
    break
  }
}

$shot3R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot3R.result.data) {
  [IO.File]::WriteAllBytes((Join-Path $artifactsDir "06_retry_warning_check.png"), [Convert]::FromBase64String($shot3R.result.data))
  Write-Host "SHOT_06_SAVED"
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

# Turns DOM
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

$dur = [int]((Get-Date)-$startTime).TotalSeconds
$timeline += "T+$dur DONE warning_hit=$warningHit convo_rid=$convoRid loading_failed=$($failedLines.Count)"

$notes = @()
$notes += "Request #641 RETRY (cdp_retry2) — huggingface check-warning A4 regression test"
$notes += "Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
$notes += "Duration: ${dur}s"
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
