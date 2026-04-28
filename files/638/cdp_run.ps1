# CDP driver for mistral PII v5 verification (#638)
$ErrorActionPreference = "Stop"
$artifactsDir = "C:\Users\최장희\Documents\dev_test_sync\files\638"

function Get-Page {
  $tabs = (Invoke-WebRequest -Uri "http://localhost:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
  return ($tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*chat.mistral.ai*" } | Select-Object -First 1)
}

$page = Get-Page
if (-not $page) { Write-Error "no mistral tab"; exit 1 }
Write-Host "PAGE_URL=$($page.url)"
Write-Host "WS=$($page.webSocketDebuggerUrl)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
$cts = New-Object System.Threading.CancellationTokenSource
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cts.Token).Wait()
Write-Host "CONNECTED state=$($ws.State)"

$global:msgId = 0
$global:responses = @{}
$global:eventLog = @()
$global:networkResponses = @{}  # requestId -> {status, headers, body}
$global:requestMeta = @{}        # requestId -> {url, method}

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

function Recv-Until($predicate, $timeoutSec = 30) {
  $buf = New-Object byte[] 65536
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $sb = New-Object Text.StringBuilder
    do {
      $seg = New-Object System.ArraySegment[byte] (,$buf)
      $recvTask = $ws.ReceiveAsync($seg, $cts.Token)
      while (-not $recvTask.IsCompleted) {
        Start-Sleep -Milliseconds 20
        if ((Get-Date) -gt $deadline) { return $null }
      }
      $r = $recvTask.Result
      if ($r.Count -gt 0) {
        $sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) | Out-Null
      }
    } while (-not $r.EndOfMessage)
    $msg = $sb.ToString()
    try { $obj = $msg | ConvertFrom-Json } catch { continue }
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
    }
    if (& $predicate $obj) { return $obj }
  }
  return $null
}

function Wait-Cmd($id, $timeoutSec = 30) {
  return Recv-Until -predicate { param($o) $o.id -eq $id } -timeoutSec $timeoutSec
}

function Eval-JS($expr) {
  $id = Send-Cmd "Runtime.evaluate" @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  $r = Wait-Cmd $id 30
  return $r
}

# Enable domains
Wait-Cmd (Send-Cmd "Network.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Page.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Runtime.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Console.enable" $null) 10 | Out-Null
Wait-Cmd (Send-Cmd "Log.enable" $null) 10 | Out-Null
Write-Host "DOMAINS_ENABLED"

# Wait for page ready (drain events 5s)
$start = Get-Date
while ((Get-Date) -lt $start.AddSeconds(5)) {
  Recv-Until -predicate { param($o) $false } -timeoutSec 1 | Out-Null
}
Write-Host "PAGE_DRAINED"

# Probe input element
$probe = Eval-JS @"
(function(){
  var inputs = document.querySelectorAll('div[contenteditable=true], textarea');
  var arr = [];
  inputs.forEach(function(el, i){ arr.push({i:i, tag:el.tagName, role:el.getAttribute('role'), placeholder:el.getAttribute('placeholder'), aria:el.getAttribute('aria-label')}); });
  return JSON.stringify(arr);
})();
"@
Write-Host "INPUTS=$($probe.result.result.value)"

# Send text via setting innerText + dispatching input event  + Enter
$prompt = '내 주민등록번호는 880101-1234567 인데 이걸로 무엇을 알 수 있어?'
$promptJsLit = $prompt -replace '\\','\\' -replace "'", "\\'"

$inject = @"
(function(){
  var el = document.querySelector('div[contenteditable=true]') || document.querySelector('textarea');
  if(!el) return 'NO_INPUT';
  el.focus();
  if(el.tagName==='TEXTAREA'){
    var setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    setter.call(el, '$promptJsLit');
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  } else {
    // contenteditable: ProseMirror needs paragraph children
    el.innerHTML = '<p>$promptJsLit</p>';
    el.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:'$promptJsLit'}));
  }
  return 'INJECTED:'+(el.tagName)+':'+(el.innerText||el.value).slice(0,40);
})();
"@
$r = Eval-JS $inject
Write-Host "INJECT=$($r.result.result.value)"
Start-Sleep -Milliseconds 700

# Try keypress Enter via CDP
function Send-Key($keyCode, $key) {
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyDown"; key = $key; code = $key; windowsVirtualKeyCode = $keyCode } | Out-Null
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyUp"; key = $key; code = $key; windowsVirtualKeyCode = $keyCode } | Out-Null
}

# focus first via JS click on the send button if visible, else Enter
$submitR = Eval-JS @"
(function(){
  var buttons = document.querySelectorAll('button');
  for(var i=0;i<buttons.length;i++){
    var b = buttons[i];
    var aria = b.getAttribute('aria-label') || '';
    if(/send|보내|submit/i.test(aria)){ if(!b.disabled){ b.click(); return 'CLICKED:'+aria; } }
  }
  return 'NO_BTN';
})();
"@
Write-Host "SUBMIT=$($submitR.result.result.value)"

if ($submitR.result.result.value -like 'NO_BTN*') {
  Write-Host "Falling back to Enter key"
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyDown"; key = "Enter"; code = "Enter"; windowsVirtualKeyCode = 13 } | Out-Null
  Send-Cmd "Input.dispatchKeyEvent" @{ type = "keyUp"; key = "Enter"; code = "Enter"; windowsVirtualKeyCode = 13 } | Out-Null
}

# Wait 12s for network activity, drain events
Write-Host "WAITING_FOR_NETWORK..."
$end = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $end) {
  Recv-Until -predicate { param($o) $false } -timeoutSec 1 | Out-Null
}

# Find newChat request
$newChatRid = $null
foreach ($k in $global:networkResponses.Keys) {
  $r = $global:networkResponses[$k]
  if ($r.url -like "*message.newChat*" -or $r.url -like "*api/trpc*newChat*") {
    $newChatRid = $k
    Write-Host "FOUND_NEWCHAT rid=$k url=$($r.url) status=$($r.status)"
    break
  }
}
if (-not $newChatRid) {
  # Print all observed URLs for debug
  Write-Host "ALL_RESPONSES:"
  foreach ($k in $global:networkResponses.Keys) { $r = $global:networkResponses[$k]; Write-Host "  rid=$k url=$($r.url) status=$($r.status)" }
}

# Get response body
if ($newChatRid) {
  $bodyId = Send-Cmd "Network.getResponseBody" @{ requestId = $newChatRid }
  $bodyR = Wait-Cmd $bodyId 15
  $body = $bodyR.result.body
  $isB64 = $bodyR.result.base64Encoded
  if ($isB64) { $body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body)) }
  Set-Content -Path "$artifactsDir\response_body.txt" -Value $body -Encoding UTF8
  $body.Substring(0, [Math]::Min(800, $body.Length)) | Set-Content -Path "$artifactsDir\response_body_preview.txt" -Encoding UTF8
  $r = $global:networkResponses[$newChatRid]
  $hdrLines = @()
  $hdrLines += "HTTP $($r.status) $($r.statusText)"
  $hdrLines += "URL: $($r.url)"
  foreach ($k in $r.headers.PSObject.Properties.Name) { $hdrLines += "${k}: $($r.headers.$k)" }
  $hdrLines | Set-Content -Path "$artifactsDir\response_headers.txt" -Encoding UTF8
  Set-Content -Path "$artifactsDir\status_line.txt" -Value "HTTP $($r.status) $($r.statusText)" -Encoding UTF8
  Write-Host "BODY_LEN=$($body.Length)"
} else {
  Set-Content -Path "$artifactsDir\status_line.txt" -Value "NO_NEWCHAT_REQUEST_OBSERVED" -Encoding UTF8
}

# Console messages: capture via Runtime.consoleAPICalled / Log.entryAdded / Runtime.exceptionThrown events
$consoleLines = @()
foreach ($e in $global:eventLog) {
  if ($e.method -eq "Runtime.consoleAPICalled") {
    $args = ($e.params.args | ForEach-Object { try { $_.value } catch { $_.description } }) -join " "
    $consoleLines += "[$($e.params.type)] $args"
  }
  if ($e.method -eq "Runtime.exceptionThrown") {
    $consoleLines += "[exception] $($e.params.exceptionDetails.text) $($e.params.exceptionDetails.exception.description)"
  }
  if ($e.method -eq "Log.entryAdded") {
    $consoleLines += "[$($e.params.entry.level)] $($e.params.entry.text)"
  }
}
$consoleLines | Set-Content -Path "$artifactsDir\console_errors.txt" -Encoding UTF8
Write-Host "CONSOLE_LINES=$($consoleLines.Count)"

# Extract page text snippet for warning detection
$txt = Eval-JS @"
(function(){
  return document.body.innerText.substring(0, 5000);
})();
"@
$pageText = $txt.result.result.value
Set-Content -Path "$artifactsDir\page_text.txt" -Value $pageText -Encoding UTF8
$warningHit = $pageText -match '보안 경고'
Write-Host "WARNING_HIT=$warningHit"

# Capture screenshot via CDP
$shotId = Send-Cmd "Page.captureScreenshot" @{ format = "png"; captureBeyondViewport = $false }
$shotR = Wait-Cmd $shotId 15
if ($shotR.result.data) {
  $bytes = [Convert]::FromBase64String($shotR.result.data)
  [IO.File]::WriteAllBytes("$artifactsDir\07_after.png", $bytes)
  [IO.File]::WriteAllBytes("$artifactsDir\08_warning_check.png", $bytes)
  Write-Host "SCREENSHOT_SAVED"
}

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()
Write-Host "DONE"
