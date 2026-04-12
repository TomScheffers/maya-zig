$times = @()
for ($i = 0; $i -lt 10; $i++) {
    $output = zig test .\src\tests.zig -O ReleaseFast --test-filter read 2>&1 | Out-String
    if ($output -match 'is: ([0-9.]+)s') {
        $t = [double]$Matches[1]
        $times += $t
        Write-Host "Run $($i+1): ${t}s"
    }
}
$avg = ($times | Measure-Object -Average).Average
$min = ($times | Measure-Object -Minimum).Minimum
$max = ($times | Measure-Object -Maximum).Maximum
Write-Host "`nResults: avg=$([math]::Round($avg, 4))s min=$([math]::Round($min, 4))s max=$([math]::Round($max, 4))s"
