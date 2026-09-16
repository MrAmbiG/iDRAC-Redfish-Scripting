#!/usr/bin/python3
#
# GetNicPxeBootSupportREDFISH. Python script using Redfish API DMTF to get NIC port PXE boot support state.
#
# _author_ = Texas Roemer <Texas_Roemer@Dell.com>
# _version_ = 1.0
#
# Copyright (c) 2026, Dell, Inc.
#
# This software is licensed to you under the GNU General Public License,
# version 2 (GPLv2). There is NO WARRANTY for this software, express or
# implied, including the implied warranties of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
# along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.
#

import argparse
import getpass
import json
import logging
import requests
import sys
import time
import warnings

from datetime import datetime
from pprint import pprint

warnings.filterwarnings("ignore")

parser = argparse.ArgumentParser(
    description="Python script using Redfish API DMTF to manage NIC PXE boot configuration on Dell iDRAC. "
                "Capabilities include: get PXEBootSupport state for all NIC ports; get or set the number of BIOS PXE "
                "devices (NumberOfPxeDevices); enable individual BIOS PXE devices and assign a NIC port interface; "
                "set the first UEFI boot order device (SetBootOrderFqdd1) to a specified PXE device; and retrieve "
                "the current UEFI boot order from DellBootSources sorted by index. Write operations automatically "
                "create a staged BIOS config job, reboot the server, monitor job completion, and verify the change. "
                "Multiple write arguments may be combined and will execute sequentially in a single script run."
)
parser.add_argument('-ip', help='iDRAC IP address', required=False)
parser.add_argument('-u', help='iDRAC username', required=False)
parser.add_argument('-p', help='iDRAC password. If not passed, script prompts for password.', required=False)
parser.add_argument('-x', help='X-Auth session token for Redfish calls', required=False)
parser.add_argument('--ssl', help='SSL cert verification for all Redfish calls, pass in "true" or "false". By default, this argument is not required and script ignores validating SSL cert for all Redfish calls.', required=False)
parser.add_argument('--script-examples', help='Get executing script examples', action='store_true', dest='script_examples', required=False)
parser.add_argument('--quiet', action='store_true', help='Suppress info prints echoed to screen')
parser.add_argument('--get-all-nic-ports', help='Get all NIC ports on the server and return FQDD and PXEBootSupport value for each port', action='store_true', dest='get_all_nic_ports', required=False)
parser.add_argument('--get-pxe-devices', help='Get current BIOS PXE device attribute values (PxeDevNEnDis and PxeDevNInterface) for all 16 PXE devices', action='store_true', dest='get_pxe_devices', required=False)
parser.add_argument('--set-number-pxe-devices', help='Set BIOS attribute NumberOfPxeDevices, pass in a value of 4, 8, 12 or 16', choices=['4', '8', '12', '16'], dest='set_number_pxe_devices', required=False)
parser.add_argument('--enable-pxe-device', help='Enable one or more BIOS PXE devices by passing in the device number(s) (1-16). For multiple devices use a comma separator (e.g. 1,2,3). Must also pass in --pxe-device-interface with a matching number of values', dest='enable_pxe_device', required=False)
parser.add_argument('--pxe-device-interface', help='NIC port FQDD(s) to set as the PXE device interface(s). For multiple interfaces use a comma separator (e.g. NIC.Slot.5-1-1,NIC.Slot.5-2-1). Must also pass in --enable-pxe-device with a matching number of values', dest='pxe_device_interface', required=False)
parser.add_argument('--set-boot-order-pxe-device', help='Set the first boot order device by passing in the PXE device ID (1-16). Sets BIOS attribute SetBootOrderFqdd1 to NIC.PxeDevice.<id>-1, then reboots and confirms via SetBootOrderEn', type=int, dest='set_boot_order_pxe_device', required=False)
parser.add_argument('--get-boot-order', help='Get current UEFI boot order sorted by Index from DellBootSources UefiBootSeq attribute', action='store_true', dest='get_boot_order', required=False)

args = vars(parser.parse_args())

if args["quiet"]:
    logging.basicConfig(format='%(message)s', stream=sys.stdout, level=logging.WARNING)
else:
    logging.basicConfig(format='%(message)s', stream=sys.stdout, level=logging.INFO)


def script_examples():
    print("""\n- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --get-all-nic-ports
  Returns FQDD and PXEBootSupport for all NIC ports.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --get-pxe-devices
  Returns current PxeDevNEnDis and PxeDevNInterface attribute values for all 16 PXE devices.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --set-number-pxe-devices 8
  Sets BIOS NumberOfPxeDevices to 8, then reboots and confirms the change.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --enable-pxe-device 1 --pxe-device-interface NIC.Slot.1-1-1
  Sets BIOS PXE device 1 to Enabled with interface NIC.Slot.1-1-1, then reboots and confirms the change.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --enable-pxe-device 1,2,3 --pxe-device-interface NIC.Slot.5-1-1,NIC.Slot.5-2-1,NIC.Slot.5-3-1
  Sets BIOS PXE devices 1, 2, and 3 to Enabled with interfaces NIC.Slot.5-1-1, NIC.Slot.5-2-1, and NIC.Slot.5-3-1
  respectively in a single PATCH call, then reboots and verifies all three attribute pairs.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -x <token> --ssl true --get-all-nic-ports
  Uses X-Auth token with SSL verification and returns PXEBootSupport for all NIC ports.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root --get-all-nic-ports
  Prompts for iDRAC password if -p is not provided.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --set-boot-order-pxe-device 16
  Sets BIOS SetBootOrderFqdd1 to NIC.PxeDevice.16-1 as first boot order device, then reboots and confirms via SetBootOrderEn.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --get-boot-order
  Returns current UEFI boot order sorted by Index from DellBootSources UefiBootSeq attribute.

- GetNicPxeBootSupportREDFISH.py -ip 192.168.0.120 -u root -p calvin --set-number-pxe-devices 8 --enable-pxe-device 2 --pxe-device-interface NIC.Slot.5-2-1 --set-boot-order-pxe-device 2
  Stacked workflow example: sets NumberOfPxeDevices to 8, then enables PXE device 2 with interface NIC.Slot.5-2-1,
  then sets PXE device 2 as the first boot order device. Each workflow completes fully (including reboot and
  verification) before the next one starts.""")
    sys.exit(0)


def redfish_get(uri):
    url = 'https://%s%s' % (idrac_ip, uri)
    if args["x"]:
        response = requests.get(url, verify=verify_cert, headers={'X-Auth-Token': args["x"]})
    else:
        response = requests.get(url, verify=verify_cert, auth=(idrac_username, idrac_password))
    return response


def find_key_recursive(obj, key_name):
    if isinstance(obj, dict):
        if key_name in obj:
            return obj[key_name]
        for value in obj.values():
            found = find_key_recursive(value, key_name)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for item in obj:
            found = find_key_recursive(item, key_name)
            if found is not None:
                return found
    return None


def get_network_device_functions_uri(adapter_data, adapter_uri):
    if isinstance(adapter_data.get("NetworkDeviceFunctions"), dict):
        ndf_uri = adapter_data["NetworkDeviceFunctions"].get("@odata.id")
        if ndf_uri:
            return ndf_uri
    return "%s/NetworkDeviceFunctions" % adapter_uri.rstrip('/')


def get_nic_ports_pxe_boot_support():
    adapters_uri = '/redfish/v1/Chassis/System.Embedded.1/NetworkAdapters'
    response = redfish_get(adapters_uri)
    try:
        data = response.json()
    except Exception:
        data = {}

    if response.status_code == 401:
        logging.error("- FAIL, status code 401 returned. Incorrect iDRAC username/password or invalid token.")
        sys.exit(0)
    if response.status_code != 200:
        logging.error("- FAIL, GET command failed for %s, status code %s returned" % (adapters_uri, response.status_code))
        logging.error(data)
        sys.exit(0)

    members = data.get('Members', [])
    if not members:
        logging.warning("- WARNING, no network adapter members found under %s" % adapters_uri)
        return

    logging.info("\n- INFO, found %s NetworkAdapters member(s)\n" % len(members))

    total_ports = 0
    for member in members:
        adapter_uri = member.get('@odata.id')
        if not adapter_uri:
            logging.warning("- WARNING, adapter member missing @odata.id, skipping")
            continue

        adapter_response = redfish_get(adapter_uri)
        if adapter_response.status_code != 200:
            logging.warning("- WARNING, GET failed for adapter %s, status code %s, skipping" % (adapter_uri, adapter_response.status_code))
            continue

        adapter_data = adapter_response.json()
        ndf_uri = get_network_device_functions_uri(adapter_data, adapter_uri)

        ndf_response = redfish_get(ndf_uri)
        if ndf_response.status_code != 200:
            logging.warning("- WARNING, GET failed for NetworkDeviceFunctions %s, status code %s, skipping" % (ndf_uri, ndf_response.status_code))
            continue

        ndf_data = ndf_response.json()
        ndf_members = ndf_data.get('Members', [])
        if not ndf_members:
            logging.warning("- WARNING, no NetworkDeviceFunctions members found under %s" % ndf_uri)
            continue

        for ndf_member in ndf_members:
            ndf_member_uri = ndf_member.get('@odata.id')
            if not ndf_member_uri:
                continue

            port_response = redfish_get(ndf_member_uri)
            if port_response.status_code != 200:
                logging.warning("- WARNING, GET failed for NIC port %s, status code %s, skipping" % (ndf_member_uri, port_response.status_code))
                continue

            port_data = port_response.json()
            fqdd = port_data.get('FQDD', port_data.get('Id', ndf_member_uri.split('/')[-1]))
            pxe_boot_support = find_key_recursive(port_data, 'PXEBootSupport')
            if pxe_boot_support is None:
                pxe_boot_support = 'NotReported'

            print("FQDD: %s, PXEBootSupport: %s" % (fqdd, pxe_boot_support))
            total_ports += 1

    if total_ports == 0:
        logging.warning("- WARNING, no NIC port PXEBootSupport data found")
    else:
        logging.info("\n- INFO, completed PXEBootSupport query for %s NIC port(s)" % total_ports)


def get_pxe_device_attributes():
    logging.info("\n- INFO, getting current BIOS PXE device attributes for all 16 PXE devices\n")
    response = redfish_get('/redfish/v1/Systems/System.Embedded.1/Bios')
    if response.status_code != 200:
        logging.error("- FAIL, GET command failed to retrieve BIOS attributes, status code %s returned" % response.status_code)
        logging.error(response.json())
        sys.exit(0)
    attributes = response.json().get('Attributes', {})
    for n in range(1, 17):
        endis_attr = "PxeDev%sEnDis" % n
        iface_attr = "PxeDev%sInterface" % n
        endis_val = attributes.get(endis_attr, 'NOT SUPPORTED')
        iface_val = attributes.get(iface_attr, 'NOT SUPPORTED')
        print("Attribute Name: %s, Value: %s" % (endis_attr, endis_val))
        print("Attribute Name: %s, Value: %s\n" % (iface_attr, iface_val))


def get_boot_order():
    logging.info("\n- INFO, getting current UEFI boot order from DellBootSources\n")
    uri = '/redfish/v1/Systems/System.Embedded.1/Oem/Dell/DellBootSources?$select=Attributes/UefiBootSeq'
    response = redfish_get(uri)
    if response.status_code != 200:
        logging.error("- FAIL, GET command failed for %s, status code %s returned" % (uri, response.status_code))
        logging.error(response.json())
        sys.exit(0)
    uefi_boot_seq = response.json().get('Attributes', {}).get('UefiBootSeq', [])
    if not uefi_boot_seq:
        logging.warning("- WARNING, UefiBootSeq attribute returned no entries")
        return
    sorted_entries = sorted(uefi_boot_seq, key=lambda e: e.get('Index', 0))
    print("%-6s %-20s %s" % ("Index", "Name", "DisplayName"))
    print("-" * 90)
    for entry in sorted_entries:
        print("%-6s %-20s %s" % (
            entry.get('Index', 'N/A'),
            entry.get('Name', 'N/A'),
            entry.get('DisplayName', 'N/A')
        ))
    logging.info("\n- INFO, %s UEFI boot order entries returned" % len(sorted_entries))


def enable_pxe_device():
    global job_id
    device_nums = [int(v.strip()) for v in str(args["enable_pxe_device"]).split(',')]
    interfaces = [v.strip() for v in str(args["pxe_device_interface"]).split(',')]
    logging.info("\n- INFO, setting BIOS PXE device attributes for %s device(s) -\n" % len(device_nums))
    attributes = {}
    for device_num, fqdd in zip(device_nums, interfaces):
        endis_attr = "PxeDev%sEnDis" % device_num
        iface_attr = "PxeDev%sInterface" % device_num
        attributes[endis_attr] = "Enabled"
        attributes[iface_attr] = fqdd
        logging.info("Attribute Name: %s, setting new value to: Enabled" % endis_attr)
        logging.info("Attribute Name: %s, setting new value to: %s" % (iface_attr, fqdd))
    logging.info("")
    payload = {
        "@Redfish.SettingsApplyTime": {"ApplyTime": "OnReset"},
        "Attributes": attributes
    }
    url = 'https://%s/redfish/v1/Systems/System.Embedded.1/Bios/Settings' % idrac_ip
    if args["x"]:
        headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
        response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
    else:
        headers = {'content-type': 'application/json'}
        response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
    if response.status_code in (200, 202):
        logging.info("- PASS, PATCH command passed to set BIOS PXE device attributes and create next reboot config job, status code %s returned" % response.status_code)
    else:
        logging.error("- FAIL, PATCH command failed, status code %s returned" % response.status_code)
        logging.error(response.json())
        sys.exit(0)
    try:
        job_id = response.headers['Location'].split("/")[-1]
    except:
        logging.error("- FAIL, unable to locate job ID in response headers")
        sys.exit(0)
    logging.info("- PASS, BIOS config job ID %s successfully created" % job_id)


def get_job_status_scheduled():
    count = 0
    while True:
        if count == 5:
            logging.error("- FAIL, GET job status retry count of 5 has been reached, script will exit")
            sys.exit(0)
        try:
            if args["x"]:
                response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/%s' % (idrac_ip, job_id), verify=verify_cert, headers={'X-Auth-Token': args["x"]})
            else:
                response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/%s' % (idrac_ip, job_id), verify=verify_cert, auth=(idrac_username, idrac_password))
        except requests.ConnectionError as error_message:
            logging.error(error_message)
            logging.info("- INFO, GET request will try again to poll job status")
            time.sleep(5)
            count += 1
            continue
        if response.status_code == 200:
            time.sleep(5)
        else:
            logging.error("- FAIL, Command failed to check job status, return code %s" % response.status_code)
            logging.error("Extended Info Message: {0}".format(response.json()))
            return
        data = response.json()
        if data['Message'] == "Task successfully scheduled.":
            logging.info("- INFO, staged config job marked as scheduled")
            break
        else:
            logging.info("- INFO, job status not scheduled, current status: %s" % data['Message'])


def reboot_server():
    if args["x"]:
        response = requests.get('https://%s/redfish/v1/Systems/System.Embedded.1' % idrac_ip, verify=verify_cert, headers={'X-Auth-Token': args["x"]})
    else:
        response = requests.get('https://%s/redfish/v1/Systems/System.Embedded.1' % idrac_ip, verify=verify_cert, auth=(idrac_username, idrac_password))
    data = response.json()
    logging.info("- INFO, current server power state is: %s" % data['PowerState'])
    if data['PowerState'] == "On":
        url = 'https://%s/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset' % idrac_ip
        payload = {'ResetType': 'GracefulShutdown'}
        if args["x"]:
            headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
            response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
        else:
            headers = {'content-type': 'application/json'}
            response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
        if response.status_code == 204:
            logging.info("- PASS, POST command passed to gracefully power OFF server")
            logging.info("- INFO, script will now verify graceful shutdown. If unable, forced shutdown will be invoked in 5 minutes")
            time.sleep(60)
            start_time = datetime.now()
        else:
            logging.error("- FAIL, Command failed to gracefully power OFF server, status code is: %s" % response.status_code)
            logging.error("Extended Info Message: {0}".format(response.json()))
            sys.exit(0)
        while True:
            if args["x"]:
                response = requests.get('https://%s/redfish/v1/Systems/System.Embedded.1' % idrac_ip, verify=verify_cert, headers={'X-Auth-Token': args["x"]})
            else:
                response = requests.get('https://%s/redfish/v1/Systems/System.Embedded.1' % idrac_ip, verify=verify_cert, auth=(idrac_username, idrac_password))
            data = response.json()
            current_time = str(datetime.now() - start_time)[0:7]
            if data['PowerState'] == "Off":
                logging.info("- PASS, verified graceful shutdown successful, server is in OFF state")
                break
            elif current_time == "0:05:00":
                logging.info("- INFO, unable to perform graceful shutdown, server will now perform forced shutdown")
                payload = {'ResetType': 'ForceOff'}
                if args["x"]:
                    headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
                    response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
                else:
                    headers = {'content-type': 'application/json'}
                    response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
                if response.status_code == 204:
                    logging.info("- PASS, POST command passed to perform forced shutdown")
                    time.sleep(60)
                    if args["x"]:
                        response = requests.get('https://%s/redfish/v1/Systems/System.Embedded.1' % idrac_ip, verify=verify_cert, headers={'X-Auth-Token': args["x"]})
                    else:
                        response = requests.get('https://%s/redfish/v1/Systems/System.Embedded.1' % idrac_ip, verify=verify_cert, auth=(idrac_username, idrac_password))
                    data = response.json()
                    if data['PowerState'] == "Off":
                        logging.info("- PASS, verified forced shutdown successful, server is in OFF state")
                        break
                    else:
                        logging.error("- FAIL, server not in OFF state, current power status is %s" % data['PowerState'])
                        sys.exit(0)
            else:
                continue
        payload = {'ResetType': 'On'}
        if args["x"]:
            headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
            response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
        else:
            headers = {'content-type': 'application/json'}
            response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
        if response.status_code == 204:
            logging.info("- PASS, POST command passed to power ON server")
        else:
            logging.error("- FAIL, Command failed to power ON server, status code is: %s" % response.status_code)
            logging.error("Extended Info Message: {0}".format(response.json()))
            sys.exit(0)
    elif data['PowerState'] == "Off":
        url = 'https://%s/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset' % idrac_ip
        payload = {'ResetType': 'On'}
        if args["x"]:
            headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
            response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
        else:
            headers = {'content-type': 'application/json'}
            response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
        if response.status_code == 204:
            logging.info("- PASS, POST command passed to power ON server")
        else:
            logging.error("- FAIL, Command failed to power ON server, status code is: %s" % response.status_code)
            logging.error("Extended Info Message: {0}".format(response.json()))
            sys.exit(0)
    else:
        logging.error("- FAIL, unable to get current server power state to perform reboot")
        sys.exit(0)


def loop_job_status_final():
    start_time = datetime.now()
    retry_count = 1
    while True:
        if retry_count == 20:
            logging.warning("- WARNING, GET command retry count of 20 has been reached, script will exit")
            sys.exit(0)
        try:
            if args["x"]:
                response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/%s' % (idrac_ip, job_id), verify=verify_cert, headers={'X-Auth-Token': args["x"]})
            else:
                response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/Jobs/%s' % (idrac_ip, job_id), verify=verify_cert, auth=(idrac_username, idrac_password))
        except requests.ConnectionError as error_message:
            logging.info("- INFO, GET request failed due to connection error, retry in 60 seconds")
            time.sleep(60)
            retry_count += 1
            continue
        current_time = (datetime.now() - start_time)
        if response.status_code != 200:
            logging.error("- FAIL, GET command failed to check job status, return code is %s" % response.status_code)
            logging.error("Extended Info Message: {0}".format(response.json()))
            return
        data = response.json()
        if str(current_time)[0:7] >= "2:00:00":
            logging.error("- FAIL, Timeout of 2 hours has been hit, script stopped")
            return
        elif "Fail" in data['Message'] or "fail" in data['Message'] or data['JobState'] == "Failed":
            logging.error("- FAIL, job ID %s failed, failed message is: %s" % (job_id, data['Message']))
            return
        elif data['JobState'] == "Completed":
            logging.info("\n--- PASS, Final Detailed Job Status Results ---\n")
            for i in data.items():
                pprint(i)
            logging.info("\n- INFO, job completed in %s" % str(current_time)[0:7])
            break
        else:
            logging.info("- INFO, job status not completed, current status: \"%s\"" % data['Message'])
            time.sleep(10)


def verify_pxe_bios_attributes():
    device_nums = [int(v.strip()) for v in str(args["enable_pxe_device"]).split(',')]
    interfaces = [v.strip() for v in str(args["pxe_device_interface"]).split(',')]
    logging.info("\n- INFO, verifying BIOS PXE device attributes for %s device(s) were applied correctly" % len(device_nums))
    uri = '/redfish/v1/Systems/System.Embedded.1/Bios'
    max_retries = 5
    for attempt in range(1, max_retries + 1):
        response = redfish_get(uri)
        if response.status_code == 200:
            break
        logging.warning("- WARNING, GET command attempt %s of %s failed for %s, status code %s returned" % (attempt, max_retries, uri, response.status_code))
        if attempt < max_retries:
            logging.info("- INFO, retrying in 30 seconds...")
            time.sleep(30)
    else:
        logging.error("- FAIL, GET command failed to retrieve BIOS attributes after %s attempts, last status code %s returned" % (max_retries, response.status_code))
        logging.error(response.json())
        return
    bios_attributes = response.json().get('Attributes', {})
    all_passed = True
    for device_num, fqdd in zip(device_nums, interfaces):
        endis_attr = "PxeDev%sEnDis" % device_num
        iface_attr = "PxeDev%sInterface" % device_num
        endis_val = bios_attributes.get(endis_attr, 'NOT FOUND')
        iface_val = bios_attributes.get(iface_attr, 'NOT FOUND')
        logging.info("- INFO, current value for %s: %s" % (endis_attr, endis_val))
        logging.info("- INFO, current value for %s: %s" % (iface_attr, iface_val))
        if endis_val == "Enabled" and iface_val == fqdd:
            logging.info("- PASS, confirmed %s set to Enabled and %s set to %s" % (endis_attr, iface_attr, fqdd))
        else:
            logging.error("- FAIL, BIOS PXE device attributes do not match expected values")
            logging.error("  Expected: %s=Enabled, %s=%s" % (endis_attr, iface_attr, fqdd))
            logging.error("  Actual:   %s=%s, %s=%s" % (endis_attr, endis_val, iface_attr, iface_val))
            all_passed = False
    if all_passed:
        logging.info("\n- PASS, all PXE device attributes verified successfully\n")
    else:
        logging.error("\n- FAIL, one or more PXE device attributes did not match expected values\n")


def set_number_pxe_devices():
    global job_id
    num_devices = args["set_number_pxe_devices"]
    payload = {
        "@Redfish.SettingsApplyTime": {"ApplyTime": "OnReset"},
        "Attributes": {
            "NumberOfPxeDevices": str(num_devices)
        }
    }
    logging.info("\n- INFO, setting BIOS attribute NumberOfPxeDevices to %s\n" % num_devices)
    url = 'https://%s/redfish/v1/Systems/System.Embedded.1/Bios/Settings' % idrac_ip
    if args["x"]:
        headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
        response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
    else:
        headers = {'content-type': 'application/json'}
        response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
    if response.status_code in (200, 202):
        logging.info("- PASS, PATCH command passed to set NumberOfPxeDevices and create next reboot config job, status code %s returned" % response.status_code)
    else:
        logging.error("- FAIL, PATCH command failed, status code %s returned" % response.status_code)
        logging.error(response.json())
        sys.exit(0)
    try:
        job_id = response.headers['Location'].split("/")[-1]
    except:
        logging.error("- FAIL, unable to locate job ID in response headers")
        sys.exit(0)
    logging.info("- PASS, BIOS config job ID %s successfully created" % job_id)


def verify_number_pxe_devices():
    expected = args["set_number_pxe_devices"]
    logging.info("\n- INFO, verifying BIOS attribute NumberOfPxeDevices was applied correctly")
    uri = '/redfish/v1/Systems/System.Embedded.1/Bios?$select=Attributes/NumberOfPxeDevices'
    max_retries = 5
    for attempt in range(1, max_retries + 1):
        response = redfish_get(uri)
        if response.status_code == 200:
            break
        logging.warning("- WARNING, GET command attempt %s of %s failed for %s, status code %s returned" % (attempt, max_retries, uri, response.status_code))
        if attempt < max_retries:
            logging.info("- INFO, retrying in 30 seconds...")
            time.sleep(30)
    else:
        logging.error("- FAIL, GET command failed to retrieve BIOS attributes after %s attempts, last status code %s returned" % (max_retries, response.status_code))
        logging.error(response.json())
        return
    actual = response.json().get('Attributes', {}).get('NumberOfPxeDevices', 'NOT FOUND')
    logging.info("- INFO, current value for NumberOfPxeDevices: %s" % actual)
    if str(actual) == expected:
        logging.info("\n- PASS, confirmed NumberOfPxeDevices set to %s\n" % expected)
    else:
        logging.error("\n- FAIL, NumberOfPxeDevices does not match expected value")
        logging.error("  Expected: %s" % expected)
        logging.error("  Actual:   %s\n" % actual)


def set_boot_order_pxe_device():
    global job_id
    device_id = args["set_boot_order_pxe_device"]
    fqdd_value = "NIC.PxeDevice.%s-1" % device_id
    logging.info("\n- INFO, checking current boot order to confirm %s exists before applying change" % fqdd_value)
    check_response = redfish_get('/redfish/v1/Systems/System.Embedded.1/Bios?$select=Attributes/SetBootOrderEn')
    if check_response.status_code != 200:
        logging.error("- FAIL, GET command failed to retrieve SetBootOrderEn attribute, status code %s returned" % check_response.status_code)
        logging.error(check_response.json())
        sys.exit(0)
    boot_order_en = check_response.json().get('Attributes', {}).get('SetBootOrderEn', '')
    boot_order_devices = [d.strip() for d in str(boot_order_en).split(',')]
    if fqdd_value not in boot_order_devices:
        logging.error("- FAIL, %s not found in current boot order (%s)" % (fqdd_value, boot_order_en))
        logging.error("- INFO, verify the PXE device ID is correct and the device is enabled before setting boot order")
        sys.exit(0)
    logging.info("- INFO, confirmed %s exists in current boot order, proceeding with PATCH" % fqdd_value)
    payload = {
        "@Redfish.SettingsApplyTime": {"ApplyTime": "OnReset"},
        "Attributes": {
            "SetBootOrderFqdd1": fqdd_value
        }
    }
    logging.info("\n- INFO, setting BIOS attribute SetBootOrderFqdd1 to %s\n" % fqdd_value)
    url = 'https://%s/redfish/v1/Systems/System.Embedded.1/Bios/Settings' % idrac_ip
    if args["x"]:
        headers = {'content-type': 'application/json', 'X-Auth-Token': args["x"]}
        response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert)
    else:
        headers = {'content-type': 'application/json'}
        response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=(idrac_username, idrac_password))
    if response.status_code in (200, 202):
        logging.info("- PASS, PATCH command passed to set SetBootOrderFqdd1 and create next reboot config job, status code %s returned" % response.status_code)
    else:
        logging.error("- FAIL, PATCH command failed, status code %s returned" % response.status_code)
        logging.error(response.json())
        sys.exit(0)
    try:
        job_id = response.headers['Location'].split("/")[-1]
    except:
        logging.error("- FAIL, unable to locate job ID in response headers")
        sys.exit(0)
    logging.info("- PASS, BIOS config job ID %s successfully created" % job_id)


def verify_boot_order_pxe_device():
    device_id = args["set_boot_order_pxe_device"]
    expected_first = "NIC.PxeDevice.%s-1" % device_id
    logging.info("\n- INFO, verifying BIOS attribute SetBootOrderEn was applied correctly")
    uri = '/redfish/v1/Systems/System.Embedded.1/Bios?$select=Attributes/SetBootOrderEn'
    max_retries = 5
    for attempt in range(1, max_retries + 1):
        response = redfish_get(uri)
        if response.status_code == 200:
            break
        logging.warning("- WARNING, GET command attempt %s of %s failed for %s, status code %s returned" % (attempt, max_retries, uri, response.status_code))
        if attempt < max_retries:
            logging.info("- INFO, retrying in 30 seconds...")
            time.sleep(30)
    else:
        logging.error("- FAIL, GET command failed to retrieve BIOS attributes after %s attempts, last status code %s returned" % (max_retries, response.status_code))
        logging.error(response.json())
        return
    actual = response.json().get('Attributes', {}).get('SetBootOrderEn', 'NOT FOUND')
    logging.info("- INFO, current value for SetBootOrderEn: %s" % actual)
    if actual == 'NOT FOUND':
        logging.error("- FAIL, SetBootOrderEn attribute not found in BIOS attributes")
        return
    first_device = str(actual).split(',')[0].strip()
    if first_device == expected_first:
        logging.info("\n- PASS, confirmed first boot order device is %s\n" % first_device)
    else:
        logging.error("\n- FAIL, first boot order device does not match expected value")
        logging.error("  Expected: %s" % expected_first)
        logging.error("  Actual first device: %s\n" % first_device)


if __name__ == "__main__":
    if args["script_examples"]:
        script_examples()

    elif args["ip"] or args["ssl"] or args["u"] or args["p"] or args["x"]:
        idrac_ip = args["ip"]
        idrac_username = args["u"]

        if args["p"]:
            idrac_password = args["p"]
        if not args["p"] and not args["x"] and args["u"]:
            idrac_password = getpass.getpass("\n- Argument -p not detected, pass in iDRAC user %s password: " % args["u"])

        if args["ssl"]:
            if args["ssl"].lower() == "true":
                verify_cert = True
            elif args["ssl"].lower() == "false":
                verify_cert = False
            else:
                verify_cert = False
        else:
            verify_cert = False

        if not idrac_ip:
            logging.error("- FAIL, argument -ip is required")
            sys.exit(0)
        if not args["x"] and (not idrac_username or not idrac_password):
            logging.error("- FAIL, pass either -x token or both -u and -p credentials")
            sys.exit(0)

        # Upfront validation for argument combinations and ranges
        if args["enable_pxe_device"] and not args["pxe_device_interface"]:
            logging.error("- FAIL, --enable-pxe-device also requires --pxe-device-interface to be passed in")
            sys.exit(0)
        if args["pxe_device_interface"] and not args["enable_pxe_device"]:
            logging.error("- FAIL, --pxe-device-interface also requires --enable-pxe-device to be passed in")
            sys.exit(0)
        if args["enable_pxe_device"]:
            device_nums = [v.strip() for v in str(args["enable_pxe_device"]).split(',')]
            interfaces = [v.strip() for v in str(args["pxe_device_interface"]).split(',')]
            if len(device_nums) != len(interfaces):
                logging.error("- FAIL, --enable-pxe-device and --pxe-device-interface must have the same number of comma-separated values (%s vs %s)" % (len(device_nums), len(interfaces)))
                sys.exit(0)
            for d in device_nums:
                if not d.isdigit() or int(d) < 1 or int(d) > 16:
                    logging.error("- FAIL, --enable-pxe-device value '%s' is invalid, each value must be an integer between 1 and 16" % d)
                    sys.exit(0)
        if args["set_boot_order_pxe_device"] and (args["set_boot_order_pxe_device"] < 1 or args["set_boot_order_pxe_device"] > 16):
            logging.error("- FAIL, --set-boot-order-pxe-device value must be between 1 and 16")
            sys.exit(0)

        # Read-only operations (mutually exclusive, no reboot required)
        if args["get_all_nic_ports"]:
            get_nic_ports_pxe_boot_support()
        elif args["get_pxe_devices"]:
            get_pxe_device_attributes()
        elif args["get_boot_order"]:
            get_boot_order()
        else:
            # Write workflows - each runs independently and sequentially when combined
            operation_detected = False

            if args["set_number_pxe_devices"]:
                operation_detected = True
                logging.info("\n- INFO, starting workflow 1 of %s: set NumberOfPxeDevices" % sum([
                    bool(args["set_number_pxe_devices"]),
                    bool(args["enable_pxe_device"] and args["pxe_device_interface"]),
                    bool(args["set_boot_order_pxe_device"])
                ]))
                set_number_pxe_devices()
                get_job_status_scheduled()
                reboot_server()
                loop_job_status_final()
                verify_number_pxe_devices()

            if args["enable_pxe_device"] and args["pxe_device_interface"]:
                operation_detected = True
                workflow_num = sum([bool(args["set_number_pxe_devices"]), True])
                total_workflows = sum([
                    bool(args["set_number_pxe_devices"]),
                    bool(args["enable_pxe_device"] and args["pxe_device_interface"]),
                    bool(args["set_boot_order_pxe_device"])
                ])
                logging.info("\n- INFO, starting workflow %s of %s: enable PXE device" % (workflow_num, total_workflows))
                enable_pxe_device()
                get_job_status_scheduled()
                reboot_server()
                loop_job_status_final()
                verify_pxe_bios_attributes()

            if args["set_boot_order_pxe_device"]:
                operation_detected = True
                workflow_num = sum([
                    bool(args["set_number_pxe_devices"]),
                    bool(args["enable_pxe_device"] and args["pxe_device_interface"]),
                    True
                ])
                total_workflows = workflow_num
                logging.info("\n- INFO, starting workflow %s of %s: set boot order PXE device" % (workflow_num, total_workflows))
                set_boot_order_pxe_device()
                get_job_status_scheduled()
                reboot_server()
                loop_job_status_final()
                verify_boot_order_pxe_device()

            if not operation_detected:
                logging.error("\n- FAIL, no operation argument detected. See help text or --script-examples for more details.")
                sys.exit(0)
    else:
        logging.error("\n- FAIL, invalid argument values or required parameters not passed in. See help text or --script-examples for more details.")
        sys.exit(0)
