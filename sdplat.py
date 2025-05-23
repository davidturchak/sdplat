#!/usr/bin/env python3
import subprocess
import argparse
import re
import csv
import datetime
import psutil
import ipaddress
import socket


# Constant for the interface name
INTERFACE = "ib0"

# Function to perform bitwise AND operation
def bitwise_and(ip1, ip2):
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
            print(f"Error: IP address or netmask not found for interface {interface}")
            exit(1)
    except Exception as e:
        print(f"Exception occurred while getting IP address and netmask: {e}")
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
        session_ips.sort(key=lambda ip: [int(part) for part in ip.split('.')])
        return session_ips
    except Exception as e:
        print(f"Exception occurred while getting session IPs: {e}")
        exit(1)

# Function to extract cnode IPs based on KUIC established sessions
def get_cnodes_session_ips():
    try:
        port = 55655
        connections = psutil.net_connections(kind='tcp')
        session_ips = set()

        # Get the network address for the INTERFACE
        interface_ip, netmask = get_ip_and_netmask(INTERFACE)
        network_address = bitwise_and(interface_ip, netmask)

        for conn in connections:
            if conn.status == psutil.CONN_ESTABLISHED and conn.raddr.port == port:
                ip = conn.raddr.ip
                # Only include IPs that belong to the same network as INTERFACE
                if bitwise_and(ip, netmask) == network_address:
                    session_ips.add(ip)

        return sorted(session_ips, key=lambda ip: [int(part) for part in ip.split('.')])
    except Exception as e:
        print(f"Exception occurred while getting session IPs: {e}")
        return []


# Function to kill existing qperf processes on each IP
def kill_existing_qperf(session_ips, network_address, ssh_password, specific_ip=None):
    for ip in session_ips:
        if specific_ip and ip == specific_ip:
            print(f"Killing existing qperf processes on {ip} (skipping network check)")
        elif bitwise_and(ip, network_address) == network_address:
            print(f"Killing existing qperf processes on {ip}")
        try:
            subprocess.run(['sshpass', '-p', ssh_password, 'ssh', '-o', 'StrictHostKeyChecking=no', ip, 'pkill qperf'], check=True)
        except subprocess.CalledProcessError as e:
            if e.returncode != 1:
                print(f"Exception occurred while killing qperf processes on {ip}: {e}")
            else:
                print(f"Looks like qperf process is not running yet on: {ip}")

# Function to transfer file to each IP in the same network address
def transfer_file(session_ips, network_address, ssh_password, specific_ip=None):
    for ip in session_ips:
        if specific_ip and ip == specific_ip:
            print(f"Transferring qperf file to {ip} (skipping network check)")
        elif bitwise_and(ip, network_address) != network_address:
            continue  # Skip if IP is not in the same network
        
        scp_command = [
            'sshpass', '-p', ssh_password, 
            'scp', '-o', 'StrictHostKeyChecking=no', 'qperf', 
            f'root@{ip}:/root/qperf'
        ]
        #print(f"Executing: {' '.join(scp_command)}")
        try:
            result = subprocess.run(scp_command, capture_output=True, text=True, check=True)
            print(f"Transfer to {ip} successful: {result.stdout}")
        except subprocess.CalledProcessError as e:
            print(f"Failed to transfer qperf to {ip}: {e.stderr}")

# Function to start qperf on each IP in the same network address
def start_qperf(session_ips, network_address, ssh_password, specific_ip=None):
    for ip in session_ips:
        if specific_ip and ip == specific_ip:
            print(f"Starting qperf on: {ip} (skipping network check)")
        elif bitwise_and(ip, network_address) == network_address:
            print(f"Starting qperf on: {ip}")
        try:
            subprocess.run(['sshpass', '-p', ssh_password, 'ssh', '-o', 'StrictHostKeyChecking=no', ip, 'nohup /root/qperf -lp 32111 </dev/null >/dev/null 2>&1 &'], check=True)
        except subprocess.CalledProcessError as e:
            if e.returncode != 1:
                print(f"Exception occurred while starting qperf processes on {ip}: {e}")
            else:
                print(f"Looks like it's a first start of: {ip}")

# Function to run latency measurement using local qperf for each IP
def run_latency_measurement(session_ips, network_address, specific_ip=None):
    latencies = []
    for ip in session_ips:
        if specific_ip and ip == specific_ip:
            print(f"Running latency measurement using local qperf for: {ip} (skipping network check)")
        elif bitwise_and(ip, network_address) == network_address:
            print(f"Running latency measurement using local qperf for: {ip}")
        try:
            result = subprocess.run(['./qperf', '-lp', '32111', '-ip', '32112', '-t', '2', '-m', '4096', '--use_bits_per_sec', ip, 'tcp_lat'], capture_output=True, text=True, check=True)
            latency_match = re.search(r'latency\s*=\s*([0-9.]+)\s*us', result.stdout, re.MULTILINE)
            if latency_match:
                latency = latency_match.group(1)
                latencies.append((ip, latency))
                print(f"Latency for {ip}: {latency} us")
            else:
                print(f"Unable to find latency value for {ip}")
        except Exception as e:
            print(f"Exception occurred while running latency measurement for {ip}: {e}")
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
        print(f"Latency data written to {output_file}")
    except Exception as e:
        print(f"Exception occurred while writing to CSV file: {e}")

# Main function
def main():
    parser = argparse.ArgumentParser(description="Transfer a file to each IP in the same network address, kill any existing qperf processes, start qperf on each one, and run latency measurement using local qperf.")
    parser.add_argument("--password", required=True, help="SSH password")
    parser.add_argument("--output", required=True, help="Output CSV file")
    parser.add_argument("--cnodes", action='store_true', help="Use cnodes session IPs instead of dnodes")
    parser.add_argument("--ip", type=str, help="Specify host IP instead of extracting dnodes or cnodes ips (for host mesurment need to open dataport1 outbound NSG on Azure)")
    parser.add_argument("--noprepare", action='store_true', help="Skip preparing steps (killing, transferring, starting qperf)")

    args = parser.parse_args()

    ssh_password = args.password
    output_file = args.output
    skip_prepare = args.noprepare

    print(f"Getting IP address and netmask for interface {INTERFACE}")
    interface_ip, netmask = get_ip_and_netmask(INTERFACE)

    network_address = bitwise_and(interface_ip, netmask)

    print("Extracting iSCSI sessions IPs")
    session_ips = []
    #print(f"Session IPs before: {session_ips}")

    if args.ip:
        session_ips = [args.ip]
    elif args.cnodes:
        session_ips = get_cnodes_session_ips()
    else:
        session_ips = get_session_ips()

    if not session_ips:
        print("Error: No session IPs found.")
        return
    #print(f"Session IPs after: {session_ips}")

    if not skip_prepare:
        print("Killing existing qperf processes on each IP")
        kill_existing_qperf(session_ips, network_address, ssh_password, specific_ip=args.ip)

        print("Transferring qperf file to each IP")
        transfer_file(session_ips, network_address, ssh_password, specific_ip=args.ip)

        print("Starting qperf service on each IP")
        start_qperf(session_ips, network_address, ssh_password, specific_ip=args.ip)

    print("Running latency measurement using local qperf")
    latencies = run_latency_measurement(session_ips, network_address, specific_ip=args.ip)

    print("Writing latency data to CSV file")
    write_to_csv(latencies, output_file, interface_ip)

if __name__ == "__main__":
    main()
