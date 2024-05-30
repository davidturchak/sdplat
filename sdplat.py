#!/usr/bin/env python3
import subprocess
import argparse
import re
import csv
import datetime

# Constant for the interface name
INTERFACE = "ib0"

# Function to perform bitwise AND operation
def bitwise_and(ip1, ip2):
    # In case of GCP as a workaround replace ip2 if it is 255.255.255.255
    if ip2 == '255.255.255.255':
        ip2 = '255.255.255.0'
    ip1_octets = list(map(int, ip1.split('.')))
    ip2_octets = list(map(int, ip2.split('.')))
    network_address = []
    for i in range(4):
        network_address.append(str(ip1_octets[i] & ip2_octets[i]))
    return '.'.join(network_address)

# Extract IP address and netmask using ifconfig
def get_ip_and_netmask(interface):
    try:
        output = subprocess.check_output(['ifconfig', interface]).decode('utf-8')
        ip_match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', output)
        netmask_match = re.search(r'netmask (\d+\.\d+\.\d+\.\d+)', output)
        if ip_match and netmask_match:
            return ip_match.group(1), netmask_match.group(1)
        else:
            print("Error: IP address or netmask not found for interface", interface)
            exit(1)
    except Exception as e:
        print("Exception occurred while getting IP address and netmask:", e)
        exit(1)

# Extract IPs from 'iscsiadm -m session' and store them in a list
def get_session_ips():
    try:
        session_ips = []
        output = subprocess.check_output(['iscsiadm', '-m', 'session']).decode('utf-8')
        for line in output.split('\n'):
            match = re.search(r'tcp:.*?(\d+\.\d+\.\d+\.\d+)', line)
            if match:
                session_ips.append(match.group(1))
        # Sort the list of IPs numerically
        session_ips.sort(key=lambda ip: [int(part) for part in ip.split('.')])
        return session_ips
    except Exception as e:
        print("Exception occurred while getting session IPs:", e)
        exit(1)

# Function to kill existing qperf processes on each IP
def kill_existing_qperf(session_ips, network_address, ssh_password):
    for ip in session_ips:
        if bitwise_and(ip, network_address) == network_address:
            print("Killing existing qperf processes on", ip)
            try:
                subprocess.run(['sshpass', '-p', ssh_password, 'ssh', '-o', 'StrictHostKeyChecking=no', ip, 'pkill qperf'], check=True)
            except subprocess.CalledProcessError as e:
                if e.returncode != 1:
                    print("Exception occurred while killing qperf processes on", ip, ":", e)
                else :
                    print("Looks like qperf process is not running yet on: ", ip)

# Function to transfer file to each IP in the same network address
def transfer_file(session_ips, network_address, ssh_password):
    for ip in session_ips:
        if bitwise_and(ip, network_address) == network_address:
            print("Transferring qperf file to", ip)
            try:
                subprocess.run(['sshpass', '-p', ssh_password, 'scp', 'qperf', '{}:'.format(ip)], check=True)
            except Exception as e:
                print("Exception occurred while transferring qperf file to", ip, ":", e)

# Function to start qperf on each IP in the same network address
def start_qperf(session_ips, network_address, ssh_password):
    for ip in session_ips:
        if bitwise_and(ip, network_address) == network_address:
            print("Starting qperf on", ip)
            try:
                subprocess.run(['sshpass', '-p', ssh_password, 'ssh', '-o', 'StrictHostKeyChecking=no', ip, 'nohup /root/qperf </dev/null >/dev/null 2>&1 & pgrep qperf'], check=True)
            except Exception as e:
                print("Exception occurred while starting qperf on", ip, ":", e)

# Function to run latency measurement using local qperf for each IP
def run_latency_measurement(session_ips, network_address):
    latencies = []
    for ip in session_ips:
        if bitwise_and(ip, network_address) == network_address:
            print("Running latency measurement using local qperf for", ip)
            try:
                result = subprocess.run(['./qperf', '-t', '2', '-m', '4096', '--use_bits_per_sec', ip, 'tcp_lat'], capture_output=True, text=True, check=True)               
                latency_match = re.search(r'latency\s*=\s*([0-9.]+)\s*us', result.stdout, re.MULTILINE)
                if latency_match:
                    latency = latency_match.group(1)
                    latencies.append((ip, latency))
                    print("Latency for", ip, ":", latency, "us")
                else:
                    print("Unable to find latency value for", ip)
            except Exception as e:
                print("Exception occurred while running latency measurement for", ip, ":", e)
    return latencies

# Function to write latency data to CSV file
def write_to_csv(latencies, output_file, interface_ip):
    try:
        timestamp = datetime.datetime.now().strftime("%d-%m-%Y %H:%M:%S")
        with open(output_file, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            writer.writerow(['Time', 'Src_IP', 'Dest_IP', 'Latency (us)'])
            for ip, latency in latencies:
                writer.writerow([timestamp, interface_ip, ip, latency])
        print("Latency data written to", output_file)
    except Exception as e:
        print("Exception occurred while writing to CSV file:", e)

# Main function
def main():
    parser = argparse.ArgumentParser(description="Transfer a file to each IP in the same network address, kill any existing qperf processes, start qperf on each one, and run latency measurement using local qperf.")
    parser.add_argument("--password", required=True, help="SSH password")
    parser.add_argument("--output", required=True, help="Output CSV file")

    args = parser.parse_args()

    ssh_password = args.password
    output_file = args.output

    print("Getting IP address and netmask for interface", INTERFACE)
    # Extract IP address and netmask
    interface_ip, netmask = get_ip_and_netmask(INTERFACE)

    # Calculate network address
    network_address = bitwise_and(interface_ip, netmask)

    print("Extracting iSCSI sessions IPs")
    # Extract session IPs
    session_ips = get_session_ips()

    print("Killing existing qperf processes on each dnode")
    # Kill existing qperf processes
    kill_existing_qperf(session_ips, network_address, ssh_password)

    print("Transferring qperf file to each dnode")
    # Transfer qperf file to each IP in the same network address
    transfer_file(session_ips, network_address, ssh_password)

    print("Starting qperf service on each dnode")
    # Start qperf on each IP in the same network address
    start_qperf(session_ips, network_address, ssh_password)

    print("Running latency measurement using local qperf")
    # Run latency measurement using local qperf for each IP
    latencies = run_latency_measurement(session_ips, network_address)

    print("Writing latency data to CSV file")
    # Write latency data to CSV file
    write_to_csv(latencies, output_file, interface_ip)

if __name__ == "__main__":
    main()