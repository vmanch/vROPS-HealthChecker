<#
Powershell vROPS Healthcheck script
v1.0 vMAN.ch, 04.05.2019 - Initial Version

   Checks several API endpoints in vROPS and if any are not reporting expected values will generate email alerts.

    Script requires Powershell v3 and above.

    Run the command below to store user and pass in secure credential XML for each environment

        $cred = Get-Credential
        $cred | Export-Clixml -Path "D:\vRops\config\vROPS.xml"

Example

.\vROPS-Healthcheck.ps1 -vip 'vrops.vMan.ch' -nodes 'vrops.vMan.ch' -email 'info@vman.ch'



#>

param
(
    [String]$vip,
    [array]$nodes,
    [String]$Email

)

#Logging Function
Function Log([String]$message, [String]$LogType, [String]$LogFile){
    $date = Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
    $message = $date + "`t" + $LogType + "`t" + $message
    $message >> $LogFile
}

#Log rotation function
function Reset-Log 
{ 
    #function checks to see if file in question is larger than the paramater specified if it is it will roll a log and delete the oldes log if there are more than x logs. 
    param([string]$fileName, [int64]$filesize = 1mb , [int] $logcount = 5) 
     
    $logRollStatus = $true 
    if(test-path $filename) 
    { 
        $file = Get-ChildItem $filename 
        if((($file).length) -ige $filesize) #this starts the log roll 
        { 
            $fileDir = $file.Directory 
            $fn = $file.name #this gets the name of the file we started with 
            $files = Get-ChildItem $filedir | ?{$_.name -like "$fn*"} | Sort-Object lastwritetime 
            $filefullname = $file.fullname #this gets the fullname of the file we started with 
            #$logcount +=1 #add one to the count as the base file is one more than the count 
            for ($i = ($files.count); $i -gt 0; $i--) 
            {  
                #[int]$fileNumber = ($f).name.Trim($file.name) #gets the current number of the file we are on 
                $files = Get-ChildItem $filedir | ?{$_.name -like "$fn*"} | Sort-Object lastwritetime 
                $operatingFile = $files | ?{($_.name).trim($fn) -eq $i} 
                if ($operatingfile) 
                 {$operatingFilenumber = ($files | ?{($_.name).trim($fn) -eq $i}).name.trim($fn)} 
                else 
                {$operatingFilenumber = $null} 
 
                if(($operatingFilenumber -eq $null) -and ($i -ne 1) -and ($i -lt $logcount)) 
                { 
                    $operatingFilenumber = $i 
                    $newfilename = "$filefullname.$operatingFilenumber" 
                    $operatingFile = $files | ?{($_.name).trim($fn) -eq ($i-1)} 
                    write-host "moving to $newfilename" 
                    move-item ($operatingFile.FullName) -Destination $newfilename -Force 
                } 
                elseif($i -ge $logcount) 
                { 
                    if($operatingFilenumber -eq $null) 
                    {  
                        $operatingFilenumber = $i - 1 
                        $operatingFile = $files | ?{($_.name).trim($fn) -eq $operatingFilenumber} 
                        
                    } 
                    write-host "deleting " ($operatingFile.FullName) 
                    remove-item ($operatingFile.FullName) -Force 
                } 
                elseif($i -eq 1) 
                { 
                    $operatingFilenumber = 1 
                    $newfilename = "$filefullname.$operatingFilenumber" 
                    write-host "moving to $newfilename" 
                    move-item $filefullname -Destination $newfilename -Force 
                } 
                else 
                { 
                    $operatingFilenumber = $i +1  
                    $newfilename = "$filefullname.$operatingFilenumber" 
                    $operatingFile = $files | ?{($_.name).trim($fn) -eq ($i-1)} 
                    write-host "moving to $newfilename" 
                    move-item ($operatingFile.FullName) -Destination $newfilename -Force    
                } 
                     
            } 
 
                     
          } 
         else 
         { $logRollStatus = $false} 
    } 
    else 
    { 
        $logrollStatus = $false 
    } 
    $LogRollStatus 
} 


#Get Stored Credentials

$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName

#cleanupLogFile
$LogFilePath = $ScriptPath + '\log\Logfile.log'
Reset-Log -fileName $LogFilePath -filesize 10mb -logcount 5

#Take all certs.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#vars
$RunDateTime = (Get-date)
$RunDateTimeReport = $RunDateTime.tostring("HH:mm:ss dd/MM/yyyy")
$RunDateTime = $RunDateTime.tostring("yyyyMMddHHmmss")
$LogFileLoc = $ScriptPath + '\Log\Logfile.log'
$mailserver = 'smtp.vman.ch'
$mailport = 25

if($Email -imatch '^.*@*.ch$'){

    Log -Message "$email matches the allowed email domains" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
    Echo "$email matches the allowed email domains"

    $cred = Import-Clixml -Path "$ScriptPath\config\smtp.xml"

    $SMTPUser = $cred.GetNetworkCredential().Username
    $SMTPPassword = $cred.GetNetworkCredential().Password
    }
    else
    {
    Log -Message "$email is not in the allowed email domains, will not send mail but report generation will continue" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
    Echo "$email is not in the allowed email domains, will not send mail but report generation will continue"
	$Email = ''
    }

#Send Email Function
Function SS64Mail($SMTPServer, $SMTPPort, $SMTPuser, $SMTPPass, $strSubject, $strBody, $strSenderemail, $strRecipientemail, $AttachFile)
   {
   [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { return $true }
      $MailMessage = New-Object System.Net.Mail.MailMessage
      $SMTPClient = New-Object System.Net.Mail.smtpClient ($SMTPServer, $SMTPPort)
	  $SMTPClient.EnableSsl = $true
	  $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPuser, $SMTPPass)
      $Recipient = New-Object System.Net.Mail.MailAddress($strRecipientemail, "Recipient")
      $Sender = New-Object System.Net.Mail.MailAddress($strSenderemail, "ODP Self Service Portal")
     
      $MailMessage.Sender = $Sender
      $MailMessage.From = $Sender
      $MailMessage.Subject = $strSubject
      $MailMessage.To.add($Recipient)
      $MailMessage.Body = $strBody
      if ($AttachFile -ne $null) {$MailMessage.attachments.add($AttachFile) }
      $SMTPClient.Send($MailMessage)
   }


################################################################
#######################SCRIPT STARTS HERE#######################
################################################################


Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
echo "Starting vRops HealthCheck script."
Log -Message "Starting vRops HealthCheck script." -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc


#Checking if the vROPs VIP is alive and how long it takes to respond, no authentication required.

Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
echo "Checking that the vROPS Load Balancer $vip is alive and responding"
Log -Message "Checking that the vROPS Load Balancer $vip is alive and responding" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

$VIPStatusDuration = measure-command {$VIPStatus = Invoke-WebRequest -Method Get -uri "https://$vip/suite-api/api/versions/current" -TimeoutSec 30 -UserAgent 'vMANHealthCheckerScripts/1.0'}

If ($VIPStatus.StatusCode -eq 200){ 

    [Int]$VIPStatusDurationMS = $VIPStatusDuration.TotalMilliseconds
    [string]$VIPStatusContent = ([xml]$VIPStatus.Content).version.releaseName

    Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
    echo "$vip running $VIPStatusContent is alive and responded with status code 200 in $VIPStatusDurationMS milliseconds"
    Log -Message "$vip running $VIPStatusContent is alive and responded in $VIPStatusDurationMS milliseconds" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

} else

{

    if ($VIPStatus){

            $VIPStatusCode = $VIPStatus.StatusCode
            [xml]$VIPStatusContent = ([xml]$VIPStatus.Content)

            Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
            echo "Unexpected return code from $vip retuned $VIPStatusCode in $VIPStatusDurationMS milliseconds, check $ScriptPath\Debug\$vip_$RunDateTime.xml"
            Log -Message "Unexpected return code from $vip retuned $VIPStatusCode in $VIPStatusDurationMS milliseconds, check $ScriptPath\Debug\$vip-$RunDateTime.xml" -LogType "ERROR-$RunDateTime" -LogFile $LogFileLoc
            [xml]$VIPStatusContent.Save("$ScriptPath\Debug\$vip-$RunDateTime.xml")

        $VIPReturn = 'ERROR'

    } else 

    {

        Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
        echo "Nothing returned from $vip, check $ScriptPath\Debug\$vip_$RunDateTime.xml"
        Log -Message "Nothing returned from $vip, check $ScriptPath\Debug\$vip-$RunDateTime.xml" -LogType "ERROR-$RunDateTime" -LogFile $LogFileLoc

        $VIPReturn = 'ERROR'
        
    }

}

$NodeStatusReport = @()
$vROPSServicesReport = @()



ForEach ($node in $nodes) {

Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
echo "Checking $node is pingable"
Log -Message "Checking $node is pingable" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

If (Test-Connection -ComputerName $node -Count 5 -Quiet){

    Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
    echo "Checking $node is reporting as ONLINE"
    Log -Message "Checking $node is reporting as ONLINE" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc
    
    $nodeStatusDuration = measure-command {$nodeStatus = Invoke-WebRequest -Method Get -uri "https://$node/suite-api/api/deployment/node/status" -TimeoutSec 30 -UserAgent 'vMANHealthCheckerScripts/1.0' -ErrorAction SilentlyContinue}

        If ($nodeStatus.StatusCode -eq 200){ 

            [Int]$NodeStatusDurationMS = $NodeStatusDuration.TotalMilliseconds
            [String]$NodeReportStatus = ([xml]$NodeStatus.Content).'node-status'.status
            [String]$nodeReportTime =  Get-Date -UFormat ([xml]$NodeStatus.Content).'node-status'.humanlyReadableSystemTime 
            Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
            echo "$Node responded with status code 200 in $NodeStatusDurationMS milliseconds, checking Service info now"
            Log -Message "$Node responded with status code 200 in $NodeStatusDurationMS milliseconds, checking Service info now" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

            If ($NodeReportStatus -eq 'ONLINE'){

                Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
                echo "$Node is reporting $NodeReportStatus, WoooHooo!!"
                Log -Message "$Node is reporting $NodeReportStatus, WoooHooo!!" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

                $NodeReturn = $NodeReportStatus

                    $NodeStatusReport += New-Object PSObject -Property @{
                    name = $node
                    ReportRunTime = $RunDateTimeReport
                    ResponseMS = $NodeStatusDurationMS
                    httpCode = $nodeStatus.StatusCode
                    NodeStatus = $NodeReturn
                    }

                    Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
                    echo "Checking services on $node"
                    Log -Message "Checking services on $node" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

                    $nodeServiceStatus = Invoke-RestMethod -Method Get -uri "https://$node/suite-api/api/deployment/node/services/info" -TimeoutSec 30 -UserAgent 'vMANHealthCheckerScripts/1.0' -ErrorAction SilentlyContinue

                    ForEach ($vRopsService in $nodeServiceStatus.services.service){



                        If ($vRopsService.health -ne "OK"){

                        Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
                        $ServiceReturn = $vRopsService.Name + ' ' + $vRopsService.health
                        echo "$node is unhealthy, reporting $ServiceReturn"
                        Log -Message "$node is unhealthy, reporting $ServiceReturn" -LogType "ERROR-$RunDateTime" -LogFile $LogFileLoc

                        $ServiceReturnCount += 1
                
                        $vROPSServicesReport  += New-Object PSObject -Property @{

                            NODE = $node
                            SERVICE = $vRopsService.Name
                            HEALTH = $vRopsService.health
                            STARTEDON = $vRopsService.startedOn
                            UPTIME = $vRopsService.uptime
                            DETAILS = $vRopsService.Details

                        }
                         Clear-Variable vROPSService,ServiceReturn,nodeStatus -ErrorAction SilentlyContinue
                         $SendEmail = $true
                         $ServiceHealthStatusBad = $true
                        }
                        }

                        If ($ServiceHealthStatusBad){

                        echo "$node is reporting $ServiceReturnCount unhealthy services."
                        Log -Message "$node is reporting $ServiceReturnCount unhealthy services." -LogType "ERROR-$RunDateTime" -LogFile $LogFileLoc
                        Clear-Variable ServiceReturnCount  -ErrorAction SilentlyContinue

                        }
                         
                } else
                        {

                        Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
                        echo "$Node status is $NodeReportStatus, further investigation required!!!"
                        Log -Message "$Node status is $NodeReportStatus, further investigation required!!!" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

                          $nodeServiceStatus = Invoke-RestMethod -Method Get -uri "https://$node/suite-api/api/deployment/node/services/info" -TimeoutSec 30 -UserAgent 'vMANHealthCheckerScripts/1.0' -ErrorAction SilentlyContinue

                            ForEach ($vRopsService in $nodeServiceStatus.services.service){

                                If ($vRopsService.health -ne "OK"){

                                Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
                                $ServiceReturn = $vRopsService.Name + ' ' + $vRopsService.health
                                echo "$node is unhealthy, reporting $ServiceReturn"
                                Log -Message "$node is unhealthy, reporting $ServiceReturn" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc

                                $ServiceReturnCount += 1
                
                                $vROPSServicesReport  += New-Object PSObject -Property @{

                                    NODE = $node
                                    SERVICE = $vRopsService.Name
                                    HEALTH = $vRopsService.health
                                    STARTEDON = $vRopsService.startedOn
                                    UPTIME = $vRopsService.uptime
                                    DETAILS = $vRopsService.Details

                                }
                                 Clear-Variable vRopsService,ServiceReturn -ErrorAction SilentlyContinue
                                 $SendEmail = $true
                                }
                                }

                        $NodeReturn = $NodeReportStatus

                        }

                } else 

                        {

                            $NodeStatusCode = $NodeStatus.StatusCode
                            [xml]$NodeStatusContent = ([xml]$NodeStatus.Content)
                            Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
                            echo "Unexpected return code from $Node retuned"
                            Log -Message "Unexpected return code from $Node retuned" -LogType "ERROR-$RunDateTime" -LogFile $LogFileLoc
                            If ($NodeStatusContent -gt '') { [xml]$NodeStatusContent.Save("$ScriptPath\Debug\$Node-$RunDateTime.xml") }

                            $NodeReturn = 'UNAVALIABLE'
                            $SendEmail = $true
							Clear-Variable nodeStatus -ErrorAction SilentlyContinue
                        }

   } else {

        Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
        echo "$node is unreachable, skipping"
        Log -Message "$node is unreachable, skipping" -LogType "INFO-$RunDateTime" -LogFile $LogFileLoc
        $NodeReturn = 'UNAVALIABLE'

            $NodeStatusReport += New-Object PSObject -Property @{
            name = $node
            ReportRunTime = $RunDateTimeReport
            ResponseMS = $NodeStatusDurationMS
            httpCode = $nodeStatus.StatusCode
            NodeStatus = $NodeReturn
            }
                 Clear-Variable node,NodeStatusDurationMS,NodeReturn,NodeStatusContent,NodeStatusDurationMS,NodeStatusCode,nodeStatus,NodeReportStatus,nodeReportTime,vROPSService,ServiceReturn -ErrorAction SilentlyContinue
                 $SendEmail = $true
            }

    }


If ($SendEmail){

        echo "Emailing $Email an alert"
        Log -Message "Emailing $Email an alert" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
            $body = "See attached report for details<br><br>"
        
        $ReportOutput = "$ScriptPath\Report\vRopsReport.xlsx"
        $NodeStatusReport | Export-Excel $ReportOutput -WorkSheetname 'NodeStatus'
        $vROPSServicesReport | Export-Excel $ReportOutput -WorkSheetname 'NodeServices'

        SS64Mail $mailserver $mailport $SMTPUser $SMTPPassword "vROPS One or more nodes on $VIP are reporting a fault or service as not running" $body $email $email $ReportOutput

        echo "Email sent to $email"
        Log -Message "Email sent to $email" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

}

echo "Script Finished"
Log -Message "Script Finished" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
