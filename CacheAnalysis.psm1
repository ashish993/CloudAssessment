function CacheAnalysis($ResourceGroup,$admin,$pass){

$hostnameurl = (Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cm"}).DefaultHostName

$Driver = Start-SeFirefox -Quiet -Headless
Enter-SeUrl "https://$($hostnameurl)/sitecore/" -Driver $Driver
Start-Sleep -Second 5
$Username = Find-SeElement -Driver $Driver -Id "Username"
$Username
Send-SeKeys -Element $Username -Keys $admin

$Password = Find-SeElement -Driver $Driver -Id "Password"
$Password
Send-SeKeys -Element $Password -Keys $pass

$Password.SendKeys([OpenQA.Selenium.Keys]::Enter)
Start-Sleep -Second 10

Enter-SeUrl "https://$($hostnameurl)/sitecore/admin/cache.aspx" -Driver $Driver
for($i=0; $i -lt 4; $i++)
{
$RefreshButton= Find-SeElement -Driver $Driver -ID "c_refresh"
$RefreshButton.Click()
Start-Sleep -Seconds 10
}

Write-host "Start Fetching Cache details" -ForegroundColor Yellow

$cachehtml = $Driver.PageSource
$cachehtml | Out-File "$PSScriptRoot $($ResourceGroup).html"
$html = New-Object -ComObject "HTMLFile"
 
$html.IHTMLDocument2_write((Get-Content -Path "$PSScriptRoot\$($ResourceGroup).html" -raw))
 
$allvalue =$html.all.tags("td") | % innerText
$output=@()
$a=19
while($a -le $allvalue.Count)
{
    $valueObject = New-Object PSObject
    $valueObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Count" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Size" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Delta" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "MaxSize" -Value $allvalue[$a]
    $a++
    $valueObject | Add-Member -MemberType NoteProperty -Name "Comment" -Value $allvalue[$a]
    $a++
    $output+= $valueObject
}
$output | ft Name,Count,Size,Delta,MaxSize
$converttohtml = @()
$converttohtml= "<div class='container'>  <h2>Sitecore Caching Analysis</h2><table class='table table-bordered'><tr><td>Name</td><td>Count</td><td>Size</td><td>Max Size</td></tr>"
foreach($val in $output)
{

switch ($val.Name)
{
    "SqlDataProvider - Prefetch data(web)" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"    }
    "web[items]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"     }
    "AccessResultCache" { $recomvalue = "<br>Recommended value of $($val.Name) is 300 MB"    }
    "web[data]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"  }
    "SqlDataProvider - Prefetch data(master)" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"   }
    "master[items]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"     }
    "master[data]" { $recomvalue = "<br>Recommended value of $($val.Name) is 1000 MB"   }
    "SqlDataProvider - Prefetch data(core)" { $recomvalue = "<br>Recommended value of $($val.Name) is 500 MB"   }
    "core[data]" { $recomvalue = "<br>Recommended value of $($val.Name) is 500 MB"   }
    "core[items]" { $recomvalue = "<br>Recommended value of $($val.Name) is 500 MB"   }
}

$recomvalue

$converttohtml += "<tr><td>$($val.Name)"+ " $($recomvalue)</td><td>$($val.Count)</td><td>$($val.Size)</td><td>$($val.MaxSize)</td></tr>"

}
$converttohtml += "</div>"

Write-host "Created Cache details" -ForegroundColor Yellow
Remove-Item -Path "$PSScriptRoot\$($ResourceGroup).html"
return $converttohtml

}
