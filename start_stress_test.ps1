# Module Name  : Start Stress Test
# Script Name  : start_stress_test.ps1
# Author       : Vineeth A.C.
# Version      : 0.1
# Last Modified: 28/12/2018 (ddMMyyyy)

Begin {
    #Ignore invalid certificate
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Verbose

    $LibFolder = "$PSScriptRoot\lib"
    Import-Module $LibFolder\datastore_stats.psm1 -ErrorAction Stop -Force

    #Importing manifest file
    $config_data = Import-PowerShellDataFile -Path .\benchmarking_manifest.psd1 -ErrorAction Stop
    $profile_data = Import-PowerShellDataFile -Path .\profile_manifest.psd1 -ErrorAction Stop
    
    try {
        #Connect to VCSA
        Connect-VIServer -Server $config_data.vCenter -ErrorAction Stop
    }
    catch {
        Write-Error "Incorrect vCenter creds!" -ErrorAction Stop
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    #Datastore list
    $datastore_list = $config_data.datastore_names

    #Cluster details
    $cluster_name = Get-Cluster -Name $config_data.cluster_name
    $hosts_in_cluster = $cluster_name | Get-VMHost
      
    #List of ESXi hostnames
    $esxi_list = $hosts_in_cluster.Name

    #DRS check
    if ("$($cluster_name.DrsEnabled)" -eq 'True') {
        #Disconnect session
        Disconnect-VIServer $config_data.vCenter -Confirm:$false
        Write-Error -Message "Disable DRS and re-run the script!" -ErrorAction Stop
    }

    
    #For connecting to VxFlex OS gateway ***** new
    #collecting gw creds
    try {
        Write-Verbose -Message "Collecting ScaleIO Gateway Creds" -Verbose
        $Credentials = Get-Credential -Message "Enter ScaleIO G/W Creds"
    }
    catch {
        Write-Error -Message "[EndRegion] Failed collecting gateway creds. Exiting!" -Verbose -ErrorAction Stop
        #Write-VerboseLog -ErrorInfo $PSItem
        #Stop-Transcript
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
    
        
}

Process {
    #Get all profile data keys
    $all_keys = $profile_data.GetEnumerator() | ForEach-Object {$_.Key}

    #Parent folder for logs for each script run
    $parent_folder = (Get-Date).tostring("dd-MM-yyyy-hh-mm-ss")

    #For reach profile defined in manifest2 do following
    for ($i=0; $i -lt $profile_data.Keys.Count; $i++) {
        #Invoke diskspd on each stress-test-vm
        get-vm -Name stress-test-vm* | ForEach-Object {Invoke-VMScript -VM $_ -ScriptText  "C:\diskspd.exe -b$($profile_data.$($all_keys[$i]).block_size) -d$($profile_data.$($all_keys[$i]).duration_in_sec) -t$($profile_data.$($all_keys[$i]).threads) -o$($profile_data.$($all_keys[$i]).OIO) -h -r -w$($profile_data.$($all_keys[$i]).write_percent) -L -Z500M -c$($profile_data.$($all_keys[$i]).workload_file_size) E:\io_stress.dat > C:\$_.txt" -ScriptType Powershell -ToolsWaitSecs 60 -GuestUser administrator -GuestPassword Dell1234 -RunAsync -Verbose -confirm:$false}
        
        
        #Test run time
        $test_duration = $profile_data.$($all_keys[$i]).duration_in_sec

        #Invoke vxflex os PD perf log collect function as a background job ****** new
        $h1 = Connect_VxFlexOS -gateway 192.168.150.100 -Credentials $Credentials
        $SIO_logs_job = Start-Job -ScriptBlock ${Function:PD_perf_logs} -ArgumentList "192.168.150.100",$h1,"4db4512700000000",$test_duration
        
        #Waiting till test duration
        Write-Verbose "$($all_keys[$i]): Storage stress test in progress. Test duration: $($profile_data.$($all_keys[$i]).duration_in_sec) seconds. Please wait!" -Verbose

        Write-Verbose -Message "Collecting VxFlex OS PD level logs of $($all_keys[$i]) test" -Verbose
        Write-Verbose -Message "Collecting datastore level logs of $($all_keys[$i]) test" -Verbose


        #During the test duration collect datastore logs
        $datastore_logs = datastore_stats -list1 $datastore_list -list2 $esxi_list -test_duration $test_duration
        #Start-Sleep (($profile_data.$($all_keys[$i]).duration_in_sec)+60) -Verbose
        Start-Sleep 60 -Verbose

        #Copy diskspd logs from stress-test-vms to local machine
        Write-Verbose "Copying diskspd logs to local machine" -Verbose
        $foldername = (Get-Date).tostring("dd-MM-yyyy-hh-mm-ss")+"-"+$all_keys[$i]
        get-vm -Name stress-test-vm* | ForEach-Object {Copy-VMGuestFile -Source c:\$_.txt -Destination c:\temp\$parent_folder\$foldername\ -VM $_ -GuestToLocal -HostUser vineetha -HostPassword Dell1234 -GuestUser administrator -GuestPassword Dell1234 -Force -ToolsWaitSecs 120} -Verbose
        
        Write-Verbose "Datastore level and VxFlex OS PD level log collection completed" -Verbose

        #Write datastore logs to profile folder
        $datastore_logs | Out-File -FilePath c:\temp\$parent_folder\$foldername\datastore_logs.txt -Verbose

        #Write SIO logs to profile folder ***** new
        $SIO_logs = $SIO_logs_job | Receive-Job 
        $SIO_logs | Out-File -FilePath c:\temp\$parent_folder\$foldername\sio_logs.txt -Verbose

        Start-Sleep 30 -Verbose
        Write-Verbose "Restarting all stress-test-vms"
        Get-VM -Name stress-test-vm* -Verbose | Restart-VMGuest -Verbose
        Start-Sleep 30 -Verbose
    }
}

End {
    Disconnect-VIServer $config_data.vCenter -Confirm:$false
}
