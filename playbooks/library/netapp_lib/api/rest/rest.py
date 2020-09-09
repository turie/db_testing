# Copyright (c) 2014 Navneet Singh.  All rights reserved.
# Copyright (c) 2015 Alex Meade.  All rights reserved.
# Copyright (c) 2015 Rushil Chugh.  All rights reserved.
# Copyright (c) 2015 Yogesh Kshirsagar.  All rights reserved.
# Copyright (c) 2015 NetApp, Inc. All Rights Reserved.

"""
REST webservice utilities
"""

import logging

import requests
from six.moves import urllib

from netapp_lib.exceptions import NetAppLibException

LOG = logging.getLogger(__name__)


class WebServicesException(NetAppLibException):
    """Web Service Failure"""
    message = "A webservice exception occurred."


class WebserviceClient(object):
    """Base client for NetApp Storage web services."""

    def __init__(self, scheme, host, port, service_path, username,
                 password, **kwargs):
        self._validate_params(scheme, host, port)
        self._create_endpoint(scheme, host, port, service_path)
        self._username = username
        self._password = password
        self._init_connection()

    def _validate_params(self, scheme, host, port):
        """Does some basic validation for web service params."""
        if host is None or port is None or scheme is None:
            raise ValueError('One of the required inputs from host, '
                             'port or scheme was not found.')
        if scheme not in ('http', 'https'):
            raise ValueError('Invalid transport type.')

    def _create_endpoint(self, scheme, host, port, service_path):
        """Creates end point url for the service."""
        netloc = '%s:%s' % (host, port)
        self._endpoint = urllib.parse.urlunparse((scheme, netloc, service_path,
                                                 None, None, None))

    def _init_connection(self):
        """Do client specific set up for session and connection pooling."""
        self.conn = requests.Session()
        if self._username and self._password:
            self.conn.auth = (self._username, self._password)

    def invoke_service(self, method='GET', url=None, params=None, data=None,
                       headers=None, timeout=None, verify=False):
        url = url or self._endpoint
        try:
            response = self.conn.request(method, url, params, data,
                                         headers=headers, timeout=timeout,
                                         verify=verify)
        # Catching error conditions other than the perceived ones.
        # Helps propagating only known exceptions back to the caller.
        except Exception:
            LOG.exception("Unexpected error while invoking web service.")
            raise WebServicesException("Invoking web service failed.")
        self._eval_response(response)
        return response

    def _eval_response(self, response):
        """Evaluates response before passing result to invoker."""
        pass
