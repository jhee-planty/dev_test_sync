#requires -Version 5
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$artifactsDir = Join-Path $env:USERPROFILE "Documents\dev_test_sync\files\641"
Write-Host "ARTIFACTS=$artifactsDir"

function Get-Page {
  $tabs = (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
  return ($tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*huggingface.co/chat*" } | Select-Object -First 1)
}

$page = Get-Page
if (-not $page) { Write-Error "no huggingface chat tab"; exit 1 }
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

Drain 3

# Dismiss "Start chatting" modal if present
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
Start-Sleep -Milliseconds 1500
Drain 2

# 01_before screenshot (after modal dismissed)
$shot1R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot1R.result.data) {
  $p1 = Join-Path $artifactsDir "01_before.png"
  [IO.File]::WriteAllBytes($p1, [Convert]::FromBase64String($shot1R.result.data))
  Write-Host "SHOT_01_SAVED"
}

# Probe textareas
$probe = Eval-JS @"
(function(){
  var inputs = document.querySelectorAll('div[contenteditable=true], textarea');
  var arr = [];
  inputs.forEach(function(el, i){ arr.push({i:i, tag:el.tagName, id:el.id, ce:el.getAttribute('contenteditable'), placeholder:el.getAttribute('placeholder'), aria:el.getAttribute('aria-label'), name:el.getAttribute('name'), visible: (el.offsetWidth>0 && el.offsetHeight>0)}); });
  return JSON.stringify(arr);
})();
"@
Write-Host "INPUTS=$($probe.result.result.value)"

# Use Input.insertText (CDP) to inject Korean — bypasses string encoding issue.
# First focus on the chat textarea (placeholder "Ask anything")
$focusR = Eval-JS @"
(function(){
  var els = document.querySelectorAll('textarea');
  for (var i=0; i<els.length; i++){
    var p = (els[i].getAttribute('placeholder')||'').toLowerCase();
    if (p.indexOf('ask') >= 0 || p.indexOf('message') >= 0 || (els[i].offsetWidth>0 && els[i].offsetHeight>0)){
      els[i].focus();
      return 'FOCUSED:'+p+':visible='+(els[i].offsetWidth>0);
    }
  }
  return 'NO_TEXTAREA';
})();
"@
Write-Host "FOCUS=$($focusR.result.result.value)"

# Insert Korean text via CDP Input.insertText (bypasses PowerShell encoding loss)
$prompt = [char]0xB0B4 + " 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?"
# Actually build prompt purely from Unicode codepoints to avoid any source-file encoding issues
$promptChars = @(
  0xB0B4, 0x0020, 0xC8FC, 0xBBFC, 0xB4F1, 0xB85D, 0xBC88, 0xD638, 0xB294, 0x0020,
  0x0038, 0x0038, 0x0030, 0x0031, 0x0030, 0x0031, 0x002D, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0020,
  0xC778, 0xB370, 0x0020, 0xC774, 0xAC78, 0xB85C, 0x0020, 0xBB34, 0xC5C7, 0xC744, 0x0020,
  0xC54C, 0x0020, 0xC218, 0x0020, 0xC788, 0xC5B4, 0x003F
)
$prompt = -join ($promptChars | ForEach-Object { [char]$_ })
Write-Host "PROMPT_LEN=$($prompt.Length) FIRST=$($prompt.Substring(0,5))"

$insertId = Send-Cmd "Input.insertText" @{ text = $prompt }
Wait-Cmd $insertId 10 | Out-Null
Start-Sleep -Milliseconds 800

# Verify
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

# Click send button
$submitR = Eval-JS @"
(function(){
  var buttons = document.querySelectorAll('button');
  for(var i=0;i<buttons.length;i++){
    var b = buttons[i];
    var aria = (b.getAttribute('aria-label') || '').toLowerCase();
    if (aria === 'send message' && !b.disabled){ b.click(); return 'CLICKED:'+aria; }
  }
  // fallback: any submit button inside form near textarea
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
  Write-Host "SHOT_02_SAVED"
}

# Wait up to 30s for response
Write-Host "WAITING_FOR_RESPONSE..."
$end = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $end) {
  Drain 2
  $tx = Eval-JS "var t=document.body.innerText; (t.indexOf('차단')>-1)||(t.indexOf('보안')>-1)||(t.indexOf('warning')>-1)||(t.indexOf('blocked')>-1)"
  if ($tx.result.result.value -eq $true) { Write-Host "WARNING_FOUND_EARLY"; break }
}

$shot3R = Wait-Cmd (Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }) 15
if ($shot3R.result.data) {
  $p3 = Join-Path $artifactsDir "03_warning_check.png"
  [IO.File]::WriteAllBytes($p3, [Convert]::FromBase64String($shot3R.result.data))
  Write-Host "SHOT_03_SAVED"
}

# Find the chat conversation request (POST /chat/conversation/{uuid})
$convoRid = $null
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  $meta = $global:requestMeta[$k]
  if ($r.url -match 'huggingface\.co/chat/conversation/[a-f0-9]+' -and $meta.method -eq 'POST') {
    $convoRid = $k
    Write-Host "FOUND_CONVO_POST rid=$k url=$($r.url) status=$($r.status)"
    break
  }
}
if (-not $convoRid) {
  foreach ($k in $global:networkResponses.Keys) {
    $r = $global:networkResponses[$k]
    if ($r.url -match 'huggingface\.co/chat/conversation/[a-f0-9]+') {
      $convoRid = $k
      Write-Host "FOUND_CONVO_ANY rid=$k url=$($r.url) status=$($r.status)"
      break
    }
  }
}

# All chat-related URLs + methods
$allUrls = @()
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  $meta = $global:requestMeta[$k]
  $m = if ($meta) { $meta.method } else { '?' }
  if ($r.url -like '*huggingface.co/chat/*' -or $r.url -match 'conversation') {
    $allUrls += "rid=$k method=$m status=$($r.status) url=$($r.url)"
  }
}
$allUrls | Set-Content -Path "$artifactsDir\all_responses.txt" -Encoding UTF8

# loadingFailed for RST_STREAM evidence
$failedLines = @()
foreach ($k in $global:loadingFailed.Keys) {
  $f = $global:loadingFailed[$k]
  $reqMeta = $global:requestMeta[$k]
  $url = if ($reqMeta) { $reqMeta.url } else { "?" }
  $method = if ($reqMeta) { $reqMeta.method } else { "?" }
  $failedLines += "rid=$k errorText=$($f.errorText) canceled=$($f.canceled) type=$($f.type) method=$method url=$url"
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

# Console / errors
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

# Assistant turn DOM
$turnsR = Eval-JS @"
(function(){
  var sels = ['div.prose.max-w-none','div.prose','[class*=prose]','[role=article]','main article'];
  var out = [];
  for (var i=0; i<sels.length; i++){
    var nodes = document.querySelectorAll(sels[i]);
    if (nodes.length>0){
      for (var j=0; j<Math.min(nodes.length, 10); j++){
        out.push({selector: sels[i], idx: j, text: (nodes[j].innerText||'').slice(0, 1000), html: (nodes[j].outerHTML||'').slice(0, 1000)});
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
