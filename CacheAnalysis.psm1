function CacheAnalysis($ResourceGroup,$admin,$pass){

$hostnameurl = (Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cm"}).DefaultHostName

$Driver = Start-SeFirefox -Quiet -Headless
Enter-SeUrl "https://$($hostnameurl)/sitecore/" -Driver $Driver
Start-Sleep -Second 5
$Username = Find-SeElement -Driver $Driver -Id "Username"
Send-SeKeys -Element $Username -Keys $admin

$Password = Find-SeElement -Driver $Driver -Id "Password"
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
$html = New-Object -ComObject "HTMLFile"
$html.IHTMLDocument2_write($cachehtml)
 
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

$converttohtml = @()
$converttohtml= "<div class='container'>  <h2>Sitecore Caching Analysis</h2><table class='table table-bordered'><tr><td>Name</td><td>Count</td><td>Size</td><td>Max Size</td></tr>"
foreach($val in $output)
{
$recomvalue=""
switch ($val.Name)
{
    "SqlDataProvider - Prefetch data(web)" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 1000 MB</b>"    }
    "web[items]" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 1000 MB</b>"     }
    "AccessResultCache" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 300 MB</b>"    }
    "web[data]" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 1000 MB</b>"  }
    "SqlDataProvider - Prefetch data(master)" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 1000 MB</b>"   }
    "master[items]" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 1000 MB</b>"     }
    "master[data]" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 1000 MB</b>"   }
    "SqlDataProvider - Prefetch data(core)" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 500 MB</b>"   }
    "core[data]" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 500 MB</b>"   }
    "core[items]" { $recomvalue = "<br><b>Recommended value of $($val.Name) is 500 MB</b>"   }
}
$converttohtml += "<tr><td>$($val.Name)"+ " $($recomvalue)</td><td>$($val.Count)</td><td>$($val.Size)</td><td>$($val.MaxSize)</td></tr>"
}
$converttohtml += "</div>"

Write-host "Created Cache details" -ForegroundColor Yellow
return $converttohtml

}
