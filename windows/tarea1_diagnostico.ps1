Write-Host "Hostname"
$env:COMPUTERNAME

Write-Host ""
Write-Host "IP" (Get-NetIPAddress -AddressFamily IPv4 | SelectInterfaceAlias, IPAddress | Form-Table -AutoSize | out-string ) | Write-Host
Write-Host ""
Write-Host "Espacio en el disco" (Get-PSDrive -PSProvider FileSystem | Select Name, Used, Free | Form-Table -AutoSize | out-string ) | Write-Host
