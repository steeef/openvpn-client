#!/bin/bash

transmission_remote="transmission-remote ${TRANSMISSION_HOST}:${TRANSMISSION_PORT}"
pia_client_id_file=/vpn/pia_client_id
port_file=/vpn/pia_port
port_assignment_url="http://209.222.18.222:2000"
#
# First get a port from PIA
#

new_client_id() {
  head -n 100 /dev/urandom | sha256sum | tr -d " -"
}

old_port="$(cat ${port_file} 2>/dev/null)"

pia_client_id="$(cat ${pia_client_id_file} 2>/dev/null)"
if [ -z "${pia_client_id}" ]; then
  echo "Generating new client id for PIA"
  pia_client_id=$(new_client_id)
  echo "${pia_client_id}" > "${pia_client_id_file}"
fi

# Get the port

# retry until port retrieved
retries=0
echo "Waiting until port retrieved."
until pia_response=$(curl --interface tun0 -s -f \
  "${port_assignment_url}/?client_id=${pia_client_id}") \
  || (( retries++ >= 30 )); do
  sleep 3
done

# Check for errors in PIA response
if [ -z "${pia_response}" ]; then
  echo "Port forwarding already enabled on this connection"
  new_port="${old_port}"
else
  new_port=$(echo "${pia_response}" | grep -oE "[0-9]+")
fi

if [ -z "${new_port}" ]; then
    echo "Could not find new port from PIA"
    exit 1
fi
echo "Got new port ${new_port} from PIA"
echo "${new_port}" > "${port_file}"

#
# Now, set port in Transmission
#


# retry until transmission is running
retries=0
echo "Waiting on transmission to start."
until ${transmission_remote} -st || (( retries++ >= 15 )); do
  sleep 5
done
# get current listening port
transmission_peer_port=$(${transmission_remote} -si \
  | grep Listenport | grep -oE '[0-9]+')

if [ "${new_port}" != "${transmission_peer_port}" ]; then
  ${transmission_remote} -p "$new_port"
else
  echo "No action needed, port hasn't changed"
fi
