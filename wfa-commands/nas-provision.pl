use strict;
use Getopt::Long;
use NaServer;
use WFAUtil;

#################################### CONSTANTS ###############################
my $TRUE  = 1;
my $FALSE = 0;

my $SQL_USER  = 'root';
my $SQL_PW    = 'Netapp123@';

# M denotes metro cluster
# S denotes standard
my %cluster_service = (
   'GFS'         => {
      'prefix' => 'M',
      'std_name' => 'nas_premium',
   },
   'Fabric'      => {
      'prefix' => 'M',
      'std_name' => 'nas_premium',
   },
   'FSU'         => {
      'prefix' => 'S',
      'std_name' => 'nas_standard',
   },
   'VFS'         => {
      'prefix' => 'S',
      'std_name' => 'nas_standard',
   },
   'EDiscovery'  => {
      'prefix' => 'S',
      'std_name' => 'nas_standard',
   },
);
###################################### MAIN ##################################
my $contact;
my $location;
my $cost_centre;
my $environment;
my $protocol;
my $storage_requirement;
my $nar_id;
my $app_short_name;
my $nis_domain;
my $nis_netgroup;
my $email_address;
my $service;

GetOptions(
  'contact=s'         => \$contact,
  'location=s'        => \$location,
  'cost_centre=s'     => \$cost_centre,
  'environment=s'     => \$environment,
  'protocol=s'        => \$protocol,
  'storage_requirement=i' => \$storage_requirement,
  'nar_id=s'           => \$nar_id,
  'app_short_name=s'  => \$app_short_name,
  'nis_domain=s'      => \$nis_domain,
  'nis_netgroup=s'    => \$nis_netgroup,
  'email_address=s'   => \$email_address,
  'service=s'         => \$service,
);

my $placement_solution = {
  'success'           => 'TRUE',
  'reason'            => 'successfully determined a placement solution',
  'std_name'          => '',
  'resources'         => {
    'ontap_aggr'      => {},
    'ontap_volume'    => {},
    'ontap_qtree'     => {},
    'nfs_export'      => {},
  }
};

if ( ! exists($cluster_service[$service]) ){
   $wfa_util->sendLog('INFO', 'invalid service requested: ' + $service);
   $placement_solution->{'success'}  = $FALSE;
   $placement_solution->{'reason'}   = 'invalid service requested: ' + $service;
   add_return_vals($placement_solution, $wfa_util);
   exit(0);
}

my $wfa_util = WFAUtil->new();

my $placement_solution{'std_name'} = $cluster_service{$service}->{'std_name'};

my $nis_is_valid = nis_is_valid($nis_domain, $nis_netgroup);
if (! $nis_is_valid->{'success'} ) {
  $wfa_util->sendLog('INFO', 'nis_is_valid failed');
  $placement_solution->{'success'}  = $FALSE;
  $placement_solution->{'reason'}   = $nis_is_valid->{'reason'};
  add_return_vals($placement_solution, $wfa_util);
  exit(0);
}

my $cluster = cluster($location, $environment, $service);
if (! $cluster->{'success'} ){
  $wfa_util->sendLog('INFO', 'cluster failed');
  $placement_solution->{'success'}  = $FALSE;
  $placement_solution->{'reason'}   = $cluster->{'reason'};
  add_return_vals($placement_solution, $wfa_util);
  exit(0);
}


my $vserver = vserver( $nis_domain, $cluster->{'ontap_cluster'}{'name'} );
if (! $vserver->{'success'}){
  $wfa_util->sendLog('INFO', 'vserver failed');
  $placement_solution->{'success'}  = $FALSE;
  $placement_solution->{'reason'}   = $vserver->{'reason'};
  add_return_vals($placement_solution, $wfa_util);
  exit(0);
}

my ($new_vol_reqd, $volume) = volume( $cluster->{'ontap_cluster'}{'name'}, $vserver->{'ontap_vserver'}->{'name'}, $protocol );
if (! $volume->{'success'}){
  $wfa_util->sendLog('INFO', 'volume failed');
  $placement_solution->{'success'}  = $FALSE;
  $placement_solution->{'reason'}   = $volume->{'reason'};
  add_return_vals($placement_solution, $wfa_util);
  exit(0);
}

#--------------------------------------------------------------------
# FIXME: RTU 21 Aug 2020
# Aggregate should not be included when a suitable volume is found,
# otherwise an inadvertent volume move could be triggered or
# the ansible module will fail because it thinks a move is requested
# but the new aggr name is not specified
#--------------------------------------------------------------------
my $aggregate = aggregate($new_vol_reqd, $cluster->{'ontap_cluster'}{'name'});
if (! $aggregate->{'success'}){
   $wfa_util->sendLog('INFO', 'aggregate failed');
   $placement_solution->{'success'}  = $FALSE;
   $placement_solution->{'reason'}   = $aggregate->{'reason'};
   add_return_vals($placement_solution, $wfa_util);
   exit(0);
}


my $qtree = qtree( $cluster->{'ontap_cluster'}{'name'}, $vserver->{'ontap_vserver'}->{'name'}, $volume->{'ontap_volume'}{'name'}, $service, $environment );
if (! $qtree->{'success'}){
  $wfa_util->sendLog('INFO', 'qtree failed');
  $placement_solution->{'success'}  = $FALSE;
  $placement_solution->{'reason'}   = $qtree->{'reason'};
  add_return_vals($placement_solution, $wfa_util);
  exit(0);
}

my $nfs_export = nfs_export( $cluster->{'ontap_cluster'}{'name'}, 
                        $vserver->{'ontap_vserver'}{'name'}, 
                        $volume->{'ontap_volume'}{'name'}, 
                        'default', 
                        [] );
if (! $nfs_export->{'success'}){
  $wfa_util->sendLog('INFO', 'nfs_export failed');
  $placement_solution->{'success'}  = $FALSE;
  $placement_solution->{'reason'}   = $nfs_export->{'reason'};
  add_return_vals($placement_solution, $wfa_util);
  exit(0);
}

$placement_solution->{'resources'} = {
  'ontap_aggr'      => $aggregate->{'ontap_aggr'},
  'ontap_volume'    => $volume->{'ontap_volume'},
  'ontap_qtree'     => $qtree->{'ontap_qtree'},
  'nfs_export'      => $nfs_export->{'nfs_export'},
};
add_return_vals($placement_solution, $wfa_util);

exit(0);


#################################### FUNCTIONS ###############################
sub nis_is_valid {
  my ( $nis_domain, $nis_netgroup ) = @_;

  return {  'success' => $TRUE, 
            'reason' => '' };
}

# Return a cluster name
sub cluster {
  my ( $region, $environment, $service ) = @_;

  # For some stupid reason we always get a row with a carriage return
  # so we get desired rows + 1
  my $CLUSTER_COL_COUNT     = 5;
  my $CLUSTER_COL_NAME      = 0;
  my $CLUSTER_COL_LOCATION  = 1;
  my $CLUSTER_COL_PRI_ADDR  = 2;
  my $CLUSTER_COL_IS_METRO  = 3;

  my $cluster_name_regex = $region .
                          '[a-zA-Z]{3}NAS' .
                          $cluster_service{$service}->{'prefix'} .
                          $environment                .
                          '[0-9]+';
  my $cluster_select_sql = 'SELECT  cluster.name,'             .
                                    'cluster.location,'         .
                                    'cluster.primary_address,'  .
                                    'cluster.is_metrocluster'   . ' ' .
                            'FROM cm_storage.cluster' . ' '       .
                            'WHERE '                              .
                                    'name regexp ' . "'" . $cluster_name_regex . "'" . ';'
                            ;
  my @rows = $wfa_util->invokeMySqlQuery($cluster_select_sql, 
    'cm_storage', 
    'localhost', 
    3306, 
    $SQL_USER, 
    $SQL_PW
  );

  my $row_count = @rows / $CLUSTER_COL_COUNT;

  if ( $row_count != 1 ){
    return {  
      'success'   => $FALSE,
      'reason'    => "returned 0 or >1 cluster rows: returned $row_count rows",
    };
  }

  return { 'success'  => $TRUE,
            'reason'  => 'Successfully found cluster',
            'ontap_cluster' => {
              'name'    => $rows[$CLUSTER_COL_NAME],
              'mgmt_ip' => $rows[$CLUSTER_COL_PRI_ADDR],
          }
  };
}
#--------------------------------------------------------------------
# FIXME: RTU 21 Aug 2020
# If a new volume is not required, return only enough attrs to
# ensure that the Ansible playbook is a no-op and can't make any
# actual changes inadvertently.
#--------------------------------------------------------------------
sub aggregate {
  my ( $new_vol_reqd, $cluster_name ) = @_;

  my $COL_COUNT         = 4;
  my $COL_CLUSTER_NAME  = 0;
  my $COL_NODE_NAME     = 1;
  my $COL_AGGR_NAME     = 2;

  my $aggr_select_sql = 'SELECT'                                                      . ' ' . 
                          'cluster.name,'                                             .
                          'node.name,'                                                .
                          'aggregate.name,'                                           . ' ' .
                        'FROM cm_storage.cluster'                                     . ' ' .
                        'JOIN cm_storage.node ON (node.cluster_id = cluster.id)'      . ' ' .
                        'JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)'  . ' ' .
                        'WHERE 1 = 1'                                . ' ' .
                          'AND cluster.name = ' . $cluster_name      . ' ' .
                          'AND aggregate.name NOT LIKE aggr0*'       . ' ' .
                        'ORDER BY aggregate.available_size_mb DESC'  .
                        ';'
      ;

   my @rows = $wfa_util->invokeMySqlQuery($cluster_select_sql, 
      'cm_storage', 
      'localhost', 
      3306, 
      $SQL_USER, 
      $SQL_PW
   );

   my $row_count = @rows / $COL_COUNT;

   if ( $row_count < 1 ){
      return {  
         'success'   => $FALSE,
         'reason'    => "failed to find a suitable aggregate on cluster: $cluster_name",
      };
   }

   return {  'success'   => $TRUE,
               'reason'    => '',
               'ontap_aggr'  => {
               'name'      => $rows[$COL_AGGR_NAME],
               'cluster'   => $rows[$COL_CLUSTER_NAME],
               'node'      => $rows[$COL_NODE_NAME],
               }
   };
}

sub vserver {
  my ( $nis_domain, $cluster_name ) = @_;

  return { 'success'        => $TRUE,
            'reason'        => '',
            'ontap_vserver' => {
              'name'          => 'nis_domain',
              'cluster_name'  => $cluster_name,
            }
  };
}

sub volume {
  my ( $cluster_name, $vserver_name, $protocol ) = @_;
   #--------------------------------------------------------------------
   # FIXME: RTU 21 Aug 2020
   # vol_data will vary, incorporate that in the regex below
   #--------------------------------------------------------------------
  my $vol_name_regex = $vserver_name . '_vol_data_' . '[0-9]{3}' . '_' . $protocol;
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
  my $vol_select = '
        SELECT
          volume.name,
          vserver.name,
          cluster.name
        FROM cm_storage.cluster
        JOIN cm_storage.vserver   ON (vserver.cluster_id  = cluster.id)
        JOIN cm_storage.volume    ON (volume.vserver_id   = vserver.id)
        JOIN cm_storage.qtree     ON (qtree.volume_id     = volume.id)
        JOIN cm_storage.quota     ON (quota.qtree_id      = qtree.id)
        WHERE 1
          AND volume.used_size_mb/volume.size_mb <= 0.80
          AND volume.name REGEXP ' . $vol_name_regex . '
        ORDER BY volume.name DESC
        ;'
    ;

   my $row_count = @rows / $COL_COUNT;

   my $vol_name = $vol_regex;
   my $new_idx;
   my $new_vol_reqd = $FALSE;
   if ( $row_count < 1 ){
      $new_idx = '001';
      $new_vol_reqd = $TRUE;
   }
   else{
      my @vol_name_flds = split('_', $vol_name_regex);
      $new_idx = sprintf("%03s", $vol_name_flds[3] + 1);
   }
   $vol_name =~ s/\[0\-9\]\{3\}/$new_idx/;

  return  {   'success'         => $TRUE,
              'reason'          => '',
              'ontap_volume'    => {
                'cluster'         => $cluster_name,
                'vserver'         => $vserver_name,
                'name'            => $vol_name,
                'junction_path'   => '/' . $vol_name,
                'size'            => 1,
                'snapshot_policy' => 'default',
                'service_level'   => 'Performance',
                'security_style'  => $protocol eq 'nfs' ? 'unix' : 'ntfs',
                'space_guarantee' => 'none',
              }
  };
}

sub qtree {
  my ( $cluster_name, $vserver_name, $vol_name, $service, $environment ) = @_;

  my $qtree_regex  = $service . '_' . $environment . '_' . '[0-9]{3}';

  my $qtree_select = '
        SELECT
          qtree.name,
          volume.name,
          vserver.name,
          cluster.name
        FROM cm_storage.cluster
        JOIN cm_storage.vserver   ON (vserver.cluster_id  = cluster.id)
        JOIN cm_storage.volume    ON (volume.vserver_id   = vserver.id)
        JOIN cm_storage.qtree     ON (qtree.volume_id     = volume.id)
        WHERE 1
          AND qtree.name REGEXP ' . $qtree_regex . '
        ORDER BY qtree.name DESC
        ;'
    ;

  my @rows = $wfa_util->invokeMySqlQuery($cluster_select_sql, 
    'cm_storage', 
    'localhost', 
    3306, 
    $SQL_USER, 
    $SQL_PW
  );

my $qtree_name;

  if ( @rows ){
    $qtree_name = $service . '_' . $environment . '_' . '001';
  }
  else{
    $qtree_name = sprintf("%s_%s_%03s", 
      $service,
      $environment,
      (split( '_', $rows[0][0]))[2]+1;
  }

  return {
            'success'           => $TRUE,
            'reason'            => '',
            'ontap_qtree'       => {
              'cluster'           => $cluster_name,
              'vserver'           => $vserver_name,
              'volume'            => $vol_name,
              'name'              => $qtree_name,
            }
  };
}

sub nfs_export {
  my ( $cluster_name, $vserver_name, $policy_name, $rules ) = @_;

  return {
            'success'           => $TRUE,
            'reason'            => '',
            'nfs_export'        => {
              'cluster'           => $cluster_name,
              'vserver'           => $vserver_name,
              'policy_name'       => $policy_name,
              'policy_rules'      => 'client_match=1.1.1.1;ro_rule=sys;rw_rule=sys;super_user_security=none;protocol=nfs,client_match=2.2.2.2;ro_rule=sys;rw_rule=sys;super_user_security=none;protocol=nfs',
            }
  };
}

sub add_return_vals {
  my ( $placement_solution, $wfa_util ) = @_;

  $wfa_util->addWfaWorkflowParameter(
    'success',
    $placement_solution->{'success'},
    $TRUE
  );

  $wfa_util->addWfaWorkflowParameter(
    'reason',
    $placement_solution->{'reason'},
    $TRUE
  );

   $wfa_util->addWfaWorkflowParameter(
      'std_name',
      $placement_solution->{'std_name'},
      $TRUE
   );

  foreach my $res_type (  keys (%{$placement_solution->{'resources'}}) ){
    foreach my $res_attr (  keys (%{$placement_solution->{'resources'}->{$res_type}}) ){
      $wfa_util->addWfaWorkflowParameter(
        $res_type . '_' . $res_attr,
        $placement_solution->{'resources'}->{$res_type}->{$res_attr},
        $TRUE
      );
    }
  }
}
