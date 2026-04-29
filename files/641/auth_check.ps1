#requires -Version 5
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$tabs = (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json" -UseBasicParsing).Content | ConvertFrom-Json
$page = $tabs | Where-Object { $_.type -eq "page" -and $_.url -like "*huggingface.co*" } | Select-Object -First 1
if (-not $page) { Write-Host "NO_HF_TAB"; exit 1 }
Write-Host "PAGE_URL=$($page.url)"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cts.Token).Wait()

$global:msgId = 0
$global:responses = @{}
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
  $buf = New-Object byte[] 65536
  $seg = New-Object System.ArraySegment[byte] (,$buf)
  $rcv = $ws.ReceiveAsync($seg, $cts.Token)
  while (-not $rcv.IsCompleted) {
    if ((Get-Date) -gt $deadline) { return $null }
    Start-Sleep -Milliseconds 30
  }
  $r = $rcv.Result
  if ($r.Count -gt 0) { $sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count)) | Out-Null }
  $msg = $sb.ToString()
  if (-not $msg) { return $null }
  try { $obj = $msg | ConvertFrom-Json } catch { return $null }
  if ($obj.id) { $global:responses[$obj.id] = $obj }
  return $obj
}
function Wait-Cmd($id, $timeoutSec = 10) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    if ($global:responses.ContainsKey($id)) { return $global:responses[$id] }
    Recv-One -timeoutSec 1 | Out-Null
  }
  return $null
}
function Eval-JS($expr) {
  $id = Send-Cmd "Runtime.evaluate" @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return Wait-Cmd $id 15
}

Wait-Cmd (Send-Cmd "Page.enable" $null) 5 | Out-Null
Wait-Cmd (Send-Cmd "Runtime.enable" $null) 5 | Out-Null

# Navigate to /chat/
$nav = Send-Cmd "Page.navigate" @{ url = "https://huggingface.co/chat/" }
Wait-Cmd $nav 10 | Out-Null
Start-Sleep -Seconds 5

$loc = Eval-JS "window.location.href"
Write-Host "AFTER_NAV_URL=$($loc.result.result.value)"

$body = Eval-JS "document.body.innerText.substring(0, 500)"
Write-Host "BODY_PREVIEW=$($body.result.result.value)"

# Check for textarea (logged in indicator) vs login form
$probe = Eval-JS @"
(function(){
  var ta = document.querySelector('textarea[placeholder]');
  var loginBtn = document.querySelector('a[href*="/login"]');
  var chatTextarea = document.querySelector('main textarea');
  return JSON.stringify({
    hasTextarea: !!ta,
    taPlaceholder: ta ? ta.getAttribute('placeholder') : null,
    hasLoginLink: !!loginBtn,
    hasChatTextarea: !!chatTextarea,
    url: window.location.href
  });
})();
"@
Write-Host "PROBE=$($probe.result.result.value)"

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()
