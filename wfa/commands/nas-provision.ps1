param (
  [parameter(Mandatory=$true, HelpMessage="Contact")]
  [string]$contact,
  
  [parameter(Mandatory=$true, HelpMessage="Desired storage location")]
  [string]$location,
  
  [parameter(Mandatory=$true, HelpMessage="Cost Centre")]
  [boolean]$cost_centre,
  
  [parameter(Mandatory=$true, HelpMessage="environment")]
  [boolean]$environment,
  
  [parameter(Mandatory=$true, HelpMessage="protocol (NFS|CIFS)")]
  [boolean]$protocol,
  
  [parameter(Mandatory=$true)]
  [int]$storage_requirement,

  [parameter(Mandatory=$true, HelpMessage="NAR ID of app")]
  [boolean]$nar_id,
  
  [parameter(Mandatory=$true, HelpMessage="Application short name")]
  [boolean]$app_short_name,
  
  [parameter(Mandatory=$true, HelpMessage="NIS Domain")]
  [boolean]$nis_domain,
  
  [parameter(Mandatory=$true, HelpMessage="NIS Netgroup")]
  [boolean]$nis_netgroup,
  
  [parameter(Mandatory=$true, HelpMessage="email address")]
  [boolean]$email_address,
  
  [parameter(Mandatory=$true, HelpMessage="service desired")]
  [boolean]$service
)


########################################################################
# FUNCTIONS
########################################################################
#-----------------------------------------------------------------------
# UTILITY FUNCTIONS
#-----------------------------------------------------------------------

function set_wfa_return_values() {
   param(
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   
   Add-WfaWorkflowParameter -Name 'success' -Value $placement_solution['success'] -AddAsReturnParameter $True
   Add-WfaWorkflowParameter -Name 'reason' -Value $placement_solution['reason'] -AddAsReturnParameter $True
   Add-WfaWorkflowParameter -Name 'std_name' -Value $placement_solution['std_name'] -AddAsReturnParameter $True

   foreach ($res_type in $placement_solution['resources'].keys ){
      foreach ($res_attr in $placement_solution['resources'][$res_type].keys ){
         Add-WfaWorkflowParameter -Name $($res_type + '_' + $res_attr) -Value $placement_solution['resources'][$res_type][$res_attr] -AddAsReturnParameter $True
      }
   }

}

function Get-WFAUserPassword () {
   param(
      [parameter(Mandatory=$true)]
      [string]$pw2get
   )

   $InstallDir = (Get-ItemProperty -Path HKLM:\Software\NetApp\WFA -Name WFAInstallDir).WFAInstallDir
   
   $string = Get-Content $InstallDir\jboss\bin\wfa.conf | Where-Object { $_.Contains($pw2get) }
   $mysplit = $string.split(":")
   $var = $mysplit[1]
   
   cd $InstallDir\bin\supportfiles\
   $string = echo $var | .\openssl.exe enc -aes-256-cbc -a  -d -salt -pass pass:netapp
  
   return $string
  }

function nis_is_valid() {
   param(
      [parameter(Mandatory=$true)]
      [string]$nis_domain,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )

   return @{
      'success' = $True;
      'reason'  = ''
   }
}

function update_chargeback_table(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$placement_solution,
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )

   $new_row = "
      INSERT INTO chargeback
      VALUES (
         NULL,
         '" + $placement_solution['resources']['ontap_cluster']['name'] + "',
         '" + $placement_solution['resources']['ontap_vserver']['name'] + "',
         '" + $placement_solution['resources']['ontap_volume']['name']  + "',
         '" + $placement_solution['resources']['ontap_qtree']['name']   + "',
         '" + $request['cost_centre']                                   + "',
         '" + $request['protocol']                                      + "',
         "  + $request['storage_requirement']                           + ",
         '" + $request['nar_id']                                        + "',
         '" + $request['app_short_name']                                + "',
         '" + $request['nis_domain']                                    + "',
         '" + $request['nis_netgroup']                                  + "',
         '" + $request['email_address']                                 + "',
         '" + $request['service']                                       + "'
      )
      ;
   "

   Invoke-MySqlQuery -query $new_row -db_user $db_user -db_pw $db_pw

}
#-----------------------------------------------------------------------
# STORAGE RESOURCE FUNCTIONS
#-----------------------------------------------------------------------
function cluster() {
   param(
      [parameter(Mandatory=$true, HelpMessage="Region")]
      [string]$region,
      [parameter(Mandatory=$true, HelpMessage="environment")]
      [string]$environment,
      [parameter(Mandatory=$true, HelpMessage="service")]
      [string]$service,
      [parameter(Mandatory=$true, HelpMessage="Cluster service mapping")]
      [hashtable]$cluster_service_map,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   
   $cluster_name_regex = $region                                  + `
                        '[a-zA-Z]{3}NAS'                          + `
                        $cluster_service_map[$service]['prefix']  + `
                        $environment                              + `
                        '[0-9]+'

   $sql = "
         SELECT
            cluster.name               AS 'name',
            cluster.location           AS 'location',
            cluster.primary_address    AS 'primary_address',
            cluster.is_metrocluster    AS 'is_metrocluster'
         FROM cm_storage.cluster
         WHERE 1
            AND name REGEXP $cluster_name_regex
         ;
   "

   Get-WfaLogger -Info -Message $( "Searching for cluster using REGEX: " + $cluster_name_regex)

   $clusters = Invoke-MySqlQuery -Query $sql -User 'root' -Password $mysql_pass
   Get-WfaLogger -Info -Message $("Found " + $cluster[0] + " clusters")

   if ( $clusters[0] -eq 1 ){
      return @{
         'success' = $True;
         'reason'  = 'Successfully found cluster';
         'ontap_cluster'   = @{
            'name'         = $clusters[1].name;
            'mgmt_ip'      = $clusters[1].primary_address
         }
      }
   }
   elseif( $clusters[0] -gt 1 ){
      return @{
         'success' = $False;
         'reason'  = 'Found multiple matching clusters, expected 1';
      }
   }
   else{
      return @{
         'success' = $False;
         'reason'  = 'Failed to find single matching cluster';
      }
   }

}

function vserver() {
   param(
      [parameter(Mandatory=$true)]
      [string]$nis_domain,
      [parameter(Mandatory=$true)]
      [string]$cluster_name,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )

   return @{
      'success'      = $true;
      'reason'       = '';
      'ontap_vserver'   = @{
         'name'         = $nis_domain;
         'cluster_name' = $cluster_name
      }
   }
}

function volume() {
   param(
      [parameter(Mandatory=$true)]
      [string]$cluster_name,
      [parameter(Mandatory=$true)]
      [string]$vserver_name,
      [parameter(Mandatory=$true)]
      [string]$protocol,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )

   #--------------------------------------------------------------------
   # FIXME: RTU 21 Aug 2020
   # vol_data will vary, incorporate that in the regex below
   #--------------------------------------------------------------------
   $vol_name_regex = $vserver_name + '_vol_data_' + '[0-9]{3}' + '_' + $protocol
   #--------------------------------------------------------------------
   # FIXME: RTU 21 Aug 2020
   # Add the following to this query:
   # 1.  Group BY volume & sum on quota rule threshold, limit that on
   #     each volume to 130% of volume size
   #--------------------------------------------------------------------
   # SELECT a volume such that:
   # 1.  name matches regex
   # 2.  Usage % is 80% or less
   # 3.  Overcommit is 130% or less
   # 4.  Protocol matches desired protocol
   # if we get 0 volumes returned, volume name uses index 001
   # else volume idx is from the 1st volume + 1
   $vol_select = "
      SELECT
         cluster.name,
         vserver.name,
         volume.name,
         qtree.name,
         quota_rule.cluster,
         quota_rule.vserver_name,
         quota_rule.quota_volume,
         quota_rule.quota_target,
         SUM(quota_rule.disk_limit)  AS 'sum_disk_limit',
         SUM(quota_rule.disk_limit)/(volume.size_mb*1024) AS 'overcommit'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON ( vserver.cluster_id = cluster.id )
      JOIN cm_storage.volume ON ( volume.vserver_id = vserver.id )
      JOIN cm_storage.qtree ON (qtree.volume_id = volume.id)
      JOIN cm_storage_quota.quota_rule   ON (
         ( quota_rule.cluster = cluster.name OR quota_rule.cluster = cluster.primary_address )
         AND quota_rule.vserver_name = vserver.name
         AND quota_rule.quota_volume = volume.name
         AND CONCAT('/vol/',volume.name,'/',qtree.name) = quota_rule.quota_target
      )
      WHERE 1
         AND qtree.name != ''
         AND qtree.name REGEXP 'GFS'
      GROUP BY volume.name
      HAVING overcommit < 3
      ORDER BY volume.used_size_mb ASC
      ;
"

   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw

   $new_vol_reqd = $False
   if ($vols[0] -ge 1){
      #----------------------------------------------------
      # We found at least 1, the 1st one in the list is the
      # least used so take that one.
      #----------------------------------------------------
      $vol_name = $vols[1].vol_name
   }
   elseif( $vols[0] -lt 1){
      #----------------------------------------------------
      # Nothing suitable it would seem.
      # 1st, find the highest existing vol idx value, then
      # increment it by 1 to for new volume name
      #----------------------------------------------------
      $vol_select = "
         SELECT
            volume.name         AS 'vol_name',
            vserver.name        AS 'vserver_name',
            cluster.name        AS 'cluster_name'
         FROM cm_storage.cluster
         JOIN cm_storage.vserver   ON (vserver.cluster_id  = cluster.id)
         JOIN cm_storage.volume    ON (volume.vserver_id   = vserver.id)
         JOIN cm_storage.qtree     ON (qtree.volume_id     = volume.id)
         WHERE 1
            AND volume.name REGEXP '$vol_name_regex'
         ORDER by volume.name DESC
         ;"

      $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
      if ( $vols[0] -ge 1 ){
         $old_idx       = ($vols[1].vol_name -replace $($vserver_name + "vol_data_"), '').split('_')[0]
         $new_idx       = "{0:d3}" -f ( [int]$old_idx + 1 )
      }
      else{
         $new_idx       = "001"
      }
      $vol_name      = $vols[1].vol_name -replace $old_idx, $new_idx
      $new_vol_reqd  = $True
   }

   if ( $protocol -eq 'nfs' ){
      $security_style = 'unix'
   }
   else{
      $security_style = 'ntfs'
   }

   return $new_vol, @{
      'success'         = $True;
      'reason'          = "successfully found suitable volume";
      'ontap_volume'    = @{
         'cluster'         = $cluster_name;
         'vserver'         = $vserver_name;
         'name'            = $vol_name;
         'junction_path'   = '/' + $vol_name;
         'security_style'  = $security_style;
      }
   }
}

function qtree() {
   param(
      [parameter(Mandatory=$true)]
      [string]$cluster_name,
      [parameter(Mandatory=$true)]
      [string]$vserver_name,
      [parameter(Mandatory=$true)]
      [string]$vol_name,
      [parameter(Mandatory=$true)]
      [boolean]$new_vol,
      [parameter(Mandatory=$true)]
      [string]$service,
      [parameter(Mandatory=$true)]
      [string]$environment,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )

   $qtree_regex = $service + '_' + $environment + '_[0-9]{3}$'

   $qtree_select = "
         SELECT
         qtree.name     AS 'qtree_name',
         volume.name    AS 'vol_name',
         vserver.name   AS 'vserver_name',
         cluster.name   AS 'cluster_name'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver   ON (vserver.cluster_id  = cluster.id)
      JOIN cm_storage.volume    ON (volume.vserver_id   = vserver.id)
      JOIN cm_storage.qtree     ON (qtree.volume_id     = volume.id)
      WHERE 1
         AND qtree.name REGEXP '$qtree_regex'
      ORDER BY qtree.name DESC
      ;
   "

   $qtrees = Invoke-MySqlQuery -query $qtree_select -user root -password $mysql_pw

   if ( $qtrees[0] -ge 1 ){
      $old_idx    = $qtrees[1].qtree_name).split('_')[2]
      $new_idx    = "{0:d3}" -f ( ([int]$old_idx + 1 )
   }
   else{
      $new_idx = '001'
   }
   $qtree_name = $qtrees[1].qtree_name -replace, $old_idx, $new_idx

   return @{
      'success'      = $True;
      'reason'       = "successfully built qtree name";
      'ontap_qtree'  = @{
         'cluster'   = $cluster_name;
         'vserver'   = $vserver_name;
         'volume'    = $vol_name;
         'name'      = $qtree_name
      }
   }
}

function aggregate(){
   param(
      [parameter(Mandatory=$true)]
      [string]$cluster_name,
      [parameter(Mandatory=$true)]
      [string]$vol_size,
      [parameter(Mandatory=$true)]
      [boolean]$new_vol_reqd,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )

   #------------------------------------------------------------
   # If a new volume is not required we just return an empty
   # list to keep downstream stuff happy.  Otherwise we try to
   # find a suitable aggregate on the indicated cluster
   #------------------------------------------------------------
   if ( -not $new_vol_reqd ){
      return @{
         'success'      = $True;
         'reason'       = "No new volume required";
         'ontap_aggregate' = @{}
      }
   }

   $aggr_select_sql = "
      SELECT
         cluster.name         AS 'cluster_name',
         node.name            AS 'node_name',
         aggregate.name       AS 'name',
      FROM cm_storage.cluster
      JOIN cm_storage.node ON (node.cluster_id = cluster.id)
      JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
      WHERE 1
         AND cluster.name = '$cluster_name'
         AND aggregate.name NOT LIKE aggr0*
      ORDER BY aggregate.available_size_mb DESC
      ;"

   $aggrs = Invoke-MySqlQuery -query $aggr_select_sql -user root -password $mysql_pw

   if ( $aggrs[0] -ge 1 ){
      return @{
         'success'      = $True;
         'reason'       = "Found suitable aggregate";
         'ontap_aggr'   = @{
            'name'      = $aggrs[1].name;
            'cluster'   = $cluster_name;
            'node'      = $aggrs[1].node_name
         }
      }
   }
   else{
      return @{
         'success'      = $False;
         'reason'       = "Failed to find aggregate with sufficient free space"
      }
   }
}

function nfs_export(){
   param(
      [parameter(Mandatory=$true)]
      [string]$cluster_name,
      [parameter(Mandatory=$true)]
      [string]$vserver_name,
      [parameter(Mandatory=$true)]
      [string]$vol_name,
      [parameter(Mandatory=$true)]
      [string]$policy_name,
      [parameter(Mandatory=$true)]
      [string]$rules,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )

   return @{
      'success'      = $True;
      'reason'       = "Testing only";
      'nfs_export'   = @{
         'cluster'      = $cluster_name;
         'vserver'      = $vserver_name;
         'policy_name'  = $policy_name;
         'policy_rules' = 'client_match=1.1.1.1;ro_rule=sys;rw_rule=sys;super_user_security=none;protocol=nfs,client_match=2.2.2.2;ro_rule=sys;rw_rule=sys;super_user_security=none;protocol=nfs'
      }
   }
}
########################################################################
# VARIABLES & CONSTANTS
########################################################################
$cluster_service_map = @{
   'GFS' = @{
      'prefix'    = 'M';
      'std_name'  = 'nas_premium'
   };
   'Fabric' = @{
      'prefix'    = 'M';
      'std_name'  = 'nas_premium'
   };
   'FSU'    = @{
      'prefix'    =  'S';
      'std_name'  = 'nas_standard'
   };
   'VFS'    = @{
      'prefix'    =  'S';
      'std_name'  =  'nas_standard'
   };
   'EDiscovery'   = @{
      'prefix'    =  'S';
      'std_name'  =  'nas_standard'
   }
}

$VOL_USAGE_MAX       = 0.8
$VOL_SIZE_STD        = 1
$VOL_OVERCOMMIT_MAX  = 1.3
########################################################################
# MAIN
########################################################################
$playground_pass  = Get-WFAUserPassword -pw2get "WFAUSER"
$mysql_pass       = Get-WFAUserPassword -pw2get "MySQL"

$request = @{
   'contact'               = $contact;
   'location'              = $location;
   'cost_centre'           = $cost_centre;
   'environment'           = $environment;
   'protocol'              = $protocol;
   'storage_requirement'   = $storage_requirement;
   'nar_id'                = $nar_id;
   'app_short_name'        = $app_short_name;
   'nis_domain'            = $nis_domain;
   'nis_netgroup'          = $nis_netgroup;
   'email_address'         = $email_address;
   'service'               = $service
}

$placement_solution = @{
   'success'         = 'TRUE';
   'reason'          = 'successfully determined a placement solution';
   'std_name'        = '';
   'resources'       = @{}
}

#---------------------------------------------------------------
# If we don't have a mapping for the service we must bail
#---------------------------------------------------------------
if ( -not $cluster_service_map.ContainsKey($service) ){
   Get-WfaLogger -Info -Message $("Failed to find service mapping for: " + $service)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = 'unsupported service requested: ' + $service
   set_wfa_return_values $placement_solution
   exit
}

$placement_solution['std_name']  = $cluster_service_map[$service]['std_name']

#---------------------------------------------------------------
# Is the NIS domain valid?
#---------------------------------------------------------------
$nis_is_valid = nis_is_valid -nis_domain $nis_domain
if ( -not $nis_is_valid['success'] ){
   $fail_msg = "requested NIS Domain is not valid: " + $nis_domain
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}

#---------------------------------------------------------------
# Get the cluster
#---------------------------------------------------------------
$cluster = cluster `
      -region $location `
      -environment $environment `
      -service $service `
      -cluster_service_map $cluster_service_map
if ( -not $cluster['success'] ){
   $fail_msg = $cluster['reason'] + ": region=" + $location + ",environment=" + $environment + ",service=" + $service
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}

#---------------------------------------------------------------
# Get the vserver that matches the NIS Domain
#---------------------------------------------------------------
$vserver = vserver `
         -nis_domain $nis_domain `
         -cluster $cluster['ontap_cluster']['name']
if ( -not $vserver['success'] ){
   $fail_msg = $vserver['reason'] + ": nis_domain=" + $request['nis_domain']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
#---------------------------------------------------------------
# We get the volume 1st here because we may or may not need to
# find an aggregate for the volume.  So grab the volume, if we
# need a new one, then we'll get a new aggr, otherwise the aggr
# function just returns an empty result.
#---------------------------------------------------------------
$new_vol_reqd, $volume = volume `
      -cluster_name $cluster['ontap_cluster']['name'] `
      -vserver_name $vserver['ontap_vserver']['name'] `
      -protocol $protocol `
      -mysql_pw $mysql_pass
if ( -not $volume['success'] ){
   $fail_msg = $volume['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}

$aggr = aggregate `
      -cluster_name $cluster['ontap_cluster']['name'] `
      -vol_size $VOL_SIZE_STD `
      -new_vol_reqd $new_vol_reqd `
      -mysql_pw $mysql_pw
if ( -not $aggr['success'] ){
   $fail_msg = $aggr['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}

$qtree = qtree -cluster_name $cluster['ontap_cluster']['name'] `
   -vserver $vserver['ontap_vserver']['name'] `
   -vol_name $volume['ontap_volume']['name'] `
   -new_vol $new_vol_reqd  `
   -service $service    `
   -environment $environment `
   -mysql_pw   $mysql_pw
if ( -not $qtree['success'] ){
   $fail_msg = $qtree['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}

$nfs_export = nfs_export `
   -cluster_name  $cluster['ontap_cluster']['name'] `
   -vserver_name  $vserver['ontap_vserver']['name'] `
   -vol_name      $volume['ontap_volume']['name']  `
   -policy_name   $policy_name   `
   -rules         $rules   `
   -mysql_pw      $mysql_pw
if ( -not $nfs_export['success'] ){
   $fail_msg = $nfs_export['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}

#---------------------------------------------------------------
# Everything was successful so consolidate and finish up
#---------------------------------------------------------------
$placement_solution['resources'] = @{
   'ontap_cluster'   = $cluster;
   'ontap_aggr'      = $aggr;
   'ontap_volume'    = $volume;
   'ontap_qtree'     = $qtree;
   'nfs_export'      = $nfs_export
}

set_wfa_return_value -placement_solution $placement_solution
update_chargeback_table `
   -placement_solution $placement_solution `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pw
