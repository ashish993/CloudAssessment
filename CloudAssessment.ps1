
$ResourceGroup ="hans-Sitecore92AS"
$subscriptionId ="6822a156-20f4-4617-94c5-8614ee7eae94"

Set-AzContext -Subscription $subscriptionId
$WarningPreference = "SilentlyContinue"
$ErrorPreference = "SilentlyContinue"

$FinalOutput =@()
$wafresult = @()
######### Check Application Gateway is provisioned or not ############
Write-Host "Checking Recommendations for WAF" -ForegroundColor Yellow
$wafdetails= Get-AzApplicationGateway -ResourceGroupName $ResourceGroup

if($wafdetails -ne $null)
{
$wafresult = "Application Gateway is provisioned in the subscription. <br>"
######### Check Firewall Mode ############

$firewallmode= $wafdetails.WebApplicationFirewallConfiguration.FirewallMode
if($firewallmode -eq "Prevention")
{
$wafresult += "WAF mode is Prevention<br>"
######### Check Disabled Rules ############
$ruledetails = $wafdetails.WebApplicationFirewallConfiguration.DisabledRuleGroups.Rules
if ($ruledetails -gt 0)
{
$wafresult += "$($ruledetails.Count) Rules are disabled. Disabling any rule groups or rules may expose you to increased security risks. <br>"
}
else
{
$wafresult += "No rules are disabled. <br>"
}
}
else
{
$wafresult += "Highly recommended to change WAF mode to Prevention to secure your Sitecore Environment.<br>"
}
}
else
{
$wafresult= "Highly recommended to provision Application Gateway WAF to secure your Sitecore Environment.<br>"
}
$FinalOutput = "<h1> Recommendations for WAF </h1><p> $($wafresult) </p>"

################################# Check Web App ####################################
$FinalOutput += "<h1> Recommendations for Azure WebApps </h1>"
$webappdetails = Get-AzWebApp -ResourceGroupName $ResourceGroup

foreach($webapp in $webappdetails)
{
$webappresult = @()
Write-Host "Checking Recommendations for $($webapp.Name)" -ForegroundColor Yellow
$config =Get-AzWebapp -ResourceGroupName $ResourceGroup -Name $webapp.Name
if($config.SiteConfig.NetFrameworkVersion -ne "v4.0")
{
    $webappresult += "Ensure that App Service .Net Stack settings should be latest.<br>"
}

if($config.SiteConfig.MinTlsVersion -ne "1.2")
{
    $webappresult += "Use the latest version of TLS encryption<br>"
}
if ($config.SiteConfig.FtpsState -eq "AllAllowed")
{
    $webappresult += "Disable FTP deployments<br>"
}
if ($config.SiteConfig.Http20Enabled -ne "True")
{
    $webappresult += "HTTP version should be latest<br>"
}
if ($config.HttpsOnly -eq "False")
{
    $webappresult += "Redirect HTTP traffic to HTTPS<br>"
}

foreach ($siteconfig in $config.SiteConfig.AppSettings) 
{
    if($siteconfig.Name -eq "WEBSITE_DYNAMIC_CACHE" -and $siteconfig.Value -ne 0)
    {
        $webappresult += "Disable Dynamic Cache<br>"
    }
}

if($config.SiteConfig.AppSettings.Name.Contains("WEBSITE_LOCAL_CACHE_OPTION"))
    {
        $webappresult += "Azure Local Cache is Enabled.<br>"
    }
    else
    {
        $webappresult += "Azure Local Cache is Disabled.<br>"
    }



#Checking App Service Plan

$appserviceplan=Get-AzAppServicePlan -ResourceGroupName $ResourceGroup -Name $($webapp.ServerFarmId.Split('/\')[-1])
if ($appserviceplan.Sku -eq "Basic")
{
   $webappresult += "Using the Basic App Service plan is not recommended.<br>"
}
# 
$backupconfig= Get-AzWebAppBackupConfiguration -ResourceGroupName $ResourceGroup -Name $webapp.Name -ErrorAction SilentlyContinue
if($backupconfig -eq $null)
{
$webappresult += "Backup Configuration not found.<br>"
}
$FinalOutput += "<p><b>Recommendations for Azure WebApp $($webapp.Name)</b><br> $($webappresult) <br></p>"
}



#Check CM IP restriction rules
$ipRestrictionwafresult = @()
#Get CM instance
$cminstance= Get-AzWebApp -ResourceGroupName $ResourceGroup | Where-Object {$_.Name -match "-cm"}
$cmRestriction =Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $ResourceGroup -Name $cminstance.Name

foreach($restriction in $cmrestriction.MainSiteAccessRestrictions)
{
    if($restriction.RuleName -eq "Allow all")
    {
        $ipRestrictionwafresult = "<b>Consider IP restrictions for CM and Application Insights IP ranges for ping checks</b>"
    }
    
}

$FinalOutput += "<p>$ipRestrictionwafresult</p>"

################################# Check Azure SQL ####################################
$sqlserverresult
$sqlserver =Get-AzSqlServer -ResourceGroupName $ResourceGroup
$sqldb = Get-AzSqlDatabase -ServerName $sqlserver.ServerName -ResourceGroupName $ResourceGroup

######## SQL Server ########
Write-Host "Checking Recommendations for Azure SQL Server" -ForegroundColor Yellow
$FinalOutput += "<h1> Recommendations for Azure SQL Server </h1><p>"

$sqlauditdetails=Get-AzSqlServerAudit -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName
if($sqlauditdetails.BlobStorageTargetState -ne "Enabled" -and $sqlauditdetails.EventHubTargetState -ne "Enabled" -and $sqlauditdetails.EventHubTargetState -ne "Enabled")
{
    $sqlserverresult += "Enable auditing on SQL Server $($sqlserver.ServerName) <br>"
}

$sqlthreatdetection=Get-AzSqlServerAdvancedThreatProtectionSetting -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName
if($sqlthreatdetection.ThreatDetectionState -eq "Disabled")
{
    $sqlserverresult += "Enable Threat Detection on SQL Server <br>"
}


$sqladmin= Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName
if($sqladmin -eq $null)
{
$sqlserverresult += "Use Azure Active Directory Authentication for authentication with SQL Server. <br>"
}
$FinalOutput += "<b>Recommendations for Azure SQL Server $db </b><br> $($sqlresult)"

######## SQL Database ########
Write-Host "Checking Recommendations for Azure Databases" -ForegroundColor Yellow

$FinalOutput += "</p><h1> Recommendations for Azure SQL Database </h1><p>"

foreach($db in $sqldb.DatabaseName)
{
$sqlresult=@()

$dbauditdetails=Get-AzSqlDatabaseAudit -ResourceGroupName $ResourceGroup -DatabaseName $db -ServerName $sqlserver.ServerName
if($auditdetails.BlobStorageTargetState -ne "Enabled" -and $auditdetails.EventHubTargetState -ne "Enabled" -and $auditdetails.EventHubTargetState -ne "Enabled")
{
    $sqlresult += "Enable auditing on $($db).<br>"
}

$dbthreatdetection=Get-AzSqlDatabaseAdvancedThreatProtectionSetting -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName -DatabaseName $db
if($dbthreatdetection.ThreatDetectionState -eq "Disabled")
{
    $sqlresult += "Enable Threat Detection on $($db).<br>"
}
$dbencryption = Get-AzSqlDatabaseTransparentDataEncryption -ResourceGroupName $ResourceGroup -ServerName $sqlserver.ServerName -DatabaseName $db
if($dbencryption.State -ne "Enabled")
{
    $sqlresult += "Enable Data Encryption on $($db).<br>"
}
$FinalOutput += "<b>Recommendations for Azure SQL Database $db </b><br> $($sqlresult) <br>"
}

################################# Check Azure CDN ####################################
Write-Host "Checking Recommendations for Azure CDN" -ForegroundColor Yellow
$cdn=Get-AzCdnProfile
if($cdn -ne $null)
{
$cdnendpoint =Get-AzCdnEndpoint -ProfileName $cdn.Name -ResourceGroupName $ResourceGroup
if($cdnendpoint -eq $null)
{
$FinalOutput += "<b>Recommendations for Azure CDN</b><br><p>No CDN found. Use Azure CDN to cache Sitecore Media Library.</p>"
}
}
else
{
$FinalOutput += "<b>Recommendations for Azure CDN</b><br><p>No CDN found. Use Azure CDN to cache Sitecore Media Library.</p>"
}

$FinalOutput |  Out-File -FilePath .\Report.html

