
import requests
import urllib3
import json
import time
import argparse
import sys
import json
from datetime import datetime, date,  timedelta
from time import sleep
##########################################################################
# CLASS DEFS
##########################################################################
#-------------------------------------------------------------------------
# WFA SERVER
#-------------------------------------------------------------------------
class wfa_server(object):
   def __init__(self, wf_name, ip, credentials, request):
      pass

      self.uuid   = None

      self.wf_name      = wf_name
      self.ip           = ip
      self.credentials  = credentials
      self.request      = request

      self.raw_placement_solution = dict()
      self.placement_solution     = dict()

   def start_wf(self):
      self.__get_wf_uuid()

      wfa_inputs  = []
      for user_input in self.request.items():
         wfa_inputs.append( { 'key': user_input[0], 'value': user_input[1] } )

      ui_payload = {
         'userInputValues': wfa_inputs
      }

      result = requests.post('https://' + self.ip + '/rest/workflows/' + self.uuid  + '/jobs/',
         auth=(self.credentials['username'],self.credentials['password']),
         verify=False,
         headers = {'Accept': 'application/json'},
         json=ui_payload )
      if result.status_code == 201:
         self.job_id = result.json()['jobId']
      else:
         raise(Exception(result.reason))

   def wait4_wf(self):
      status = requests.get('https://' + self.ip + '/rest/workflows/' + self.uuid + '/jobs/' + str(self.job_id),
         auth=(self.credentials['username'],self.credentials['password']),
         verify=False,
         headers = {'Accept': 'application/json'} )
      job_status = status.json()['jobStatus']['jobStatus']
      while job_status != 'COMPLETED':
         time.sleep(5)
         status = requests.get('https://' + self.ip + '/rest/workflows/' + self.uuid + '/jobs/' + str(self.job_id),
            auth=(self.credentials['username'],self.credentials['password']),
            verify=False,
            headers = {'Accept': 'application/json'} )
         job_status = status.json()['jobStatus']['jobStatus']
      raw_ret_vals = status.json()['jobStatus']['returnParameters']
      
      for raw_ret_val in raw_ret_vals:
         self.raw_placement_solution.update( {raw_ret_val['key']: raw_ret_val['value'] } )
      
      self.__normalize_placement_solution()

   def get_placement_solution(self):
     return self.placement_solution

   def __normalize_placement_solution(self):
      nfs_export = dict()
      for attr, value in self.raw_placement_solution.items():
         if ( attr in ['success', 'reason', 'std_name'] ):
            if attr == 'success' and value == 'TRUE':
               self.success = True
            elif attr == 'success' and value == 'FALSE':
               self.success = False
            elif attr == 'std_name':
               self.std_name = value
            else:
               self.reason = value

            continue

         res_type   = '_'.join(attr.split('_')[0:2])
         attr_name  = '_'.join(attr.split('_')[2:])
         if not res_type in self.placement_solution:
            self.placement_solution[res_type] = dict()
         if res_type != 'nfs_export':
            self.placement_solution[res_type][attr_name] = value
         else:
            nfs_export.update( { attr_name: value } )
      self.__normalize_nfs_export(nfs_export)

   def __normalize_nfs_export(self, nfs_export):
      print(json.dumps(nfs_export))
      self.placement_solution['nfs_export'] = dict()
      self.placement_solution['nfs_export'].update( {
               'policies': [
                  {
                     'name'   :              nfs_export['policy_name'],
                     'vserver':              nfs_export['vserver'],
                     'controller_name':      nfs_export['hostname'],
                  }
               ],
               'volumes':  [
                  {
                     'vol_name':          self.placement_solution['ontap_volume']['name'],
                     'vserver':           self.placement_solution['ontap_volume']['vserver'],
                     'policy_name':       nfs_export['policy_name'],
                     'conotroller_name':  self.placement_solution['ontap_volume']['hostname'],
                  }
               ],
               'rules':    []
         }
      )
      for rule in nfs_export['policy_rules'].split(','):
         tmp_rule = dict()
         for rule_field in rule.split(';'):
            tmp_attr, tmp_val = rule_field.split('=')
            tmp_rule.update( 
               {
                  tmp_attr: tmp_val
               }
            )
         self.placement_solution['nfs_export']['rules'].append(tmp_rule)

   def __get_wf_uuid(self):
      wf = requests.get('https://' + self.ip + '/rest/workflows?name=' + self.wf_name,
         auth=(self.credentials['username'],self.credentials['password']),
         verify=False,
         headers = {'Accept': 'application/json'} )
      self.uuid   = wf.json()[0]['uuid']

#-------------------------------------------------------------------------
# DB RUN SERVER
#-------------------------------------------------------------------------
class dbrun(object):
   def __init__(self):
      pass

    
   def post_request(self, request):
      pass

#-------------------------------------------------------------------------
# SNOW
#-------------------------------------------------------------------------
class snow(object):
   def __init__(self, snow_params):
      self.snow_user    = snow_params['user']
      self.snow_pw      = snow_params['pw']
      self.snow_host    = snow_params['host']

      self.snow_headers = {
         "Content-Type":"application/json",
         "Accept":"application/json"
      }

   def new_req_comment(self, comment):
      url = 'https://' + self.snow_host + '/api/now/table/sc_request/' + self.snow_req['sys_id']
      data = {'comments': comment}
      response = requests.patch(url, 
         auth=(self.snow_user, self.snow_pw), 
         headers=self.snow_headers,
         json=data)
      if response.status_code == 200:
         self.get_req(self.snow_req['number'])
      else:
         raise(Exception(response.json()))

   def get_req(self, snow_req_number):
      response = requests.get('https://' + self.snow_host + '/api/now/table/sc_request?sysparm_query=number%3D' + snow_req_number + '&sysparm_display_value=true', 
         auth=(self.snow_user, self.snow_pw), 
         headers=self.snow_headers
      )
      if response.status_code != 200:
         raise(Exception(response.json()))
      
      self.snow_req = response.json()['result'][0]

   def get_req_attr(self, attr):
      return self.snow_req[attr]

   def get_incident(self, incident_number):
      response = requests.get('https://' + self.snow_host + '/api/now/table/incident?sysparm_query=number%3D' + incident_number + '&sysparm_display_value=true', 
         auth=(self.snow_user, self.snow_pw), 
         headers=self.snow_headers
      )
      if response.status_code != 200:
         raise(Exception(response.json()))

      self.snow_incident = response.json()['result'][0]

   def new_incident(self, short_description, additional_notes, caller):
      data = {
         'short_description':          short_description,
         'comments_and_work_notes'  :  additional_notes,
         'caller':                     caller
      }
      url = 'https://' + self.snow_host + '/api/now/table/incident'
      response = requests.post(url, 
         auth=(self.snow_user, self.snow_pw), 
         headers=self.snow_headers,
         json=data)
      if response.status_code == 201:
         self.snow_incident = response.json()['result']
      else:
         raise(Exception(response.json()))

   def get_incident_attr(self, attr):
      return self.snow_incident[attr]


#-------------------------------------------------------------------------
# AWX
#-------------------------------------------------------------------------
class awx(object):
  def __init__(self, host, template_name,  credentials, rest_protocol='http'):
    self.template_name  = template_name
    #self.extra_vars     = extra_vars
    self.credentials    = credentials
    self.host           = host
    self.rest_protocol  = rest_protocol

  def __get_template_id(self):
    #try:
    req = requests.get(self.rest_protocol + "://" + self.host + "/api/v2/job_templates?name=" + self.template_name,          
      auth=(self.credentials['user'], self.credentials['password']), 
      verify=False)
    #except:
      # print("failed to get template id: " + req.reason)
      # sys.exit(1)
    #print(req.json())
    self.template_id = req.json()['results'][0]['id']

  def launch_job(self):
    self.__get_template_id()
    try:
      # req = requests.post( "https://" + self.host + "/api/v2/job_templates/" + str(self.template_id) + "/launch/", 
      #     auth=(self.credentials['user'], self.credentials['password']), 
      #     json=self.extra_vars,
      #     verify=False)
      req = requests.post( self.rest_protocol + "://" + self.host + "/api/v2/job_templates/" + str(self.template_id) + "/launch/", 
          auth=(self.credentials['user'], self.credentials['password']), 
          verify=False)
    except:
      print("failed to launch job")
      sys.exit(1)
    self.job = req.json()

  def wait4job(self):
    req = requests.get( self.rest_protocol + "://" + self.host + "/api/v2/jobs/" + str(self.job['job']) + "/", 
      auth=(self.credentials['user'], self.credentials['password']),
      verify=False )

    status = req.json()
    finished = status['finished']
    while not finished:
      req = requests.get( self.rest_protocol + "://" + self.host + "/api/v2/jobs/" + str(self.job['job']) + "/", 
          auth=(self.credentials['user'], self.credentials['password']),
          verify=False )
      status = req.json()
      finished = status['finished']

  def get_job(self):
    return self.job



##########################################################################
# MAIN
##########################################################################
snow_params = {
   'user':  'admin',
   'pw':    'Netapp123@',
   'host':  'dev61783.service-now.com'
}

urllib3.disable_warnings (urllib3.exceptions.InsecureRequestWarning)

parser = argparse.ArgumentParser()

parser.add_argument('-w', '--wf-name',          required=True)
parser.add_argument('-s', '--wf-server-ip',     required=True)
parser.add_argument('-u', '--wf-username',      required=True)
parser.add_argument('-p', '--wf-password',      required=True)
parser.add_argument('-r', '--req-payload',      required=True)
# parser.add_argument('--snow-req-number',        required=False)

# parser.add_argument('--awx-host',               required=True)
# parser.add_argument('--awx-template-name',      required=True)
# parser.add_argument('--awx-extra-vars',         required=False)
# parser.add_argument('--awx-user',               required=True)
# parser.add_argument('--awx-password',           required=True)

args = parser.parse_args()

# snow_srvr = snow( snow_params )
# snow_srvr.get_req( args.snow_req_number)

wfa = wfa_server(args.wf_name, args.wf_server_ip, {'username': args.wf_username, 'password': args.wf_password}, json.loads(args.req_payload) )
wfa.start_wf()
wfa.wait4_wf()
print(wfa.get_placement_solution())

# if not wfa.success:
#    snow_srvr.new_incident(wfa.reason, args.req_payload, 'storage-ops@db.com')
#    snow_srvr.new_req_comment(wfa.reason)
#    sys.exit(0)

# db_request = dict()
# db_request['raw_servce_request'] = {
#    'req_details': wfa.get_placement_solution(),
#    'service':     'nfs_export',
#    'operation':   'create',
#    'std_name':    wfa.std_name
# }

# awx_srvr = awx(args.awx_host, args.awx_template_name,  { 'user': args.awx_user, 'password': args.awx_password})
# awx_srvr.launch_job()
# awx_srvr.wait4job()

# print(awx_srvr.get_job())


