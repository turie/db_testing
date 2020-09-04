

function Get-WFAUserPassword () {
 $InstallDir = (Get-ItemProperty -Path HKLM:\Software\NetApp\WFA -Name WFAInstallDir).WFAInstallDir
 
 $string = Get-Content $InstallDir\jboss\bin\wfa.conf | Where-Object { $_.Contains($pw2get) }
 $mysplit = $string.split(":")
 $var = $mysplit[1]
 
 cd $InstallDir\bin\supportfiles\
 $string = echo $var | .\openssl.exe enc -aes-256-cbc -a  -d -salt -pass pass:netapp

 return $string
}

$pw2get = "WFAUSER"
$playground_pass = Get-WFAUserPassword
$pw2get = "MySQL"
$mysql_pass = Get-WFAUserPassword


Add-WfaWorkflowParameter -Name playground_pw -Value $('WFAUSER=' + $playground_pass + ':' + 'MySQL=' + $mysql_pass)
