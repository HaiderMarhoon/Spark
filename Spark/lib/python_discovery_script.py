import sys
import time
import json
import subprocess
import platform
import os
import xml.etree.ElementTree as ET

NMAP_EXECUTABLE_PATH = "C:\\Program Files (x86)\\Nmap\\nmap.exe" # <-- CONFIGURE WITH YOUR NMAP PATH

# NOTES
# Using the range from your latest script: 172.20.10.0/28 ( MoAyoob iPhone Hotspot)
# If you switch back to your regular Wi-Fi, you might need to change this
# back to 192.168.0.0/24 or similar.
NETWORK_RANGE = "172.20.10.0/28" # <-- ADJUST IF YOUR NETWORK CHANGES


# Define a list of common ports to scan. You can expand this list.
COMMON_PORTS = "22,80,443,8080,8000,3389" # YOU CAN ADD MORE BUT WAJD W8T YA54

def scan_network_details(network_range, ports):

    sys.stderr.write(f"Python script: Starting nmap scan on {network_range} for ports {ports}...\n")
    sys.stderr.write("Attempting to retrieve IP, MAC, Vendor, and Open Port information.\n")
    # Note: Getting MAC addresses reliably might require running the script as Administrator/root.
    sys.stderr.flush()

    nmap_command = [
        NMAP_EXECUTABLE_PATH, # Use the absolute path
        "-p", ports,          # Specify ports to scan
        "-T4",                # Aggressive timing
        "--noninteractive",
        "--system-dns",       # Attempt to resolve hostnames using DNS
        "-oX", "-",           # Output XML to nmap's stdout
        network_range
    ]

    sys.stderr.write(f"Executing command: {' '.join(nmap_command)}\n")
    # Adding a note about privileges for MAC address retrieval and scan types
    if platform.system() == "Windows":
        sys.stderr.write("Note: On Windows, run this script as Administrator for best MAC/port detection results.\n")
    else:
        sys.stderr.write("Note: On Linux/macOS, run this script with sudo for best MAC/port detection results (e.g., for SYN scans).\n")
    sys.stderr.flush()

    try:
        # Check if the nmap executable exists at the specified path
        if not os.path.exists(NMAP_EXECUTABLE_PATH):
            sys.stderr.write(f"Error: nmap executable not found at {NMAP_EXECUTABLE_PATH}\n")
            sys.stderr.write("Please update NMAP_EXECUTABLE_PATH in the script with the correct path.\n")
            sys.stderr.flush()
            return [] # Return empty list on error

        # Execute the nmap command
        process = subprocess.Popen(
            nmap_command,
            stdout=subprocess.PIPE, # Capture nmap's stdout
            stderr=subprocess.PIPE, # Capture nmap's stderr
            text=True, # Decode streams as text
            creationflags=subprocess.CREATE_NO_WINDOW if platform.system() == "Windows" else 0 # Hide console window on Windows
        )

        # Communicate with the process to get stdout and stderr
        nmap_stdout, nmap_stderr = process.communicate()

        # Print nmap's stderr to our stderr for debugging
        if nmap_stderr:
            sys.stderr.write("--- nmap stderr ---\n")
            sys.stderr.write(nmap_stderr)
            sys.stderr.write("-------------------\n")
            sys.stderr.flush()


        if process.returncode != 0:
            sys.stderr.write(f"nmap process failed with error code {process.returncode}\n")
            sys.stderr.flush()
            # Don't return yet, maybe partial XML was generated

        sys.stderr.write("nmap scan completed. Processing XML output from stdout.\n")
        sys.stderr.flush()

        # Parse the XML output from nmap's stdout
        try:
            # Load the XML output. It might be empty or malformed if nmap failed or found nothing.
            if not nmap_stdout.strip():
                sys.stderr.write("Nmap stdout is empty (no XML output received).\n")
                sys.stderr.flush()
                return []

            # Find the start of the XML content (look for the XML declaration)
            xml_start_index = nmap_stdout.find('<?xml')
            if xml_start_index == -1:
                sys.stderr.write("Could not find XML declaration in nmap stdout.\n")
                sys.stderr.write(f"Raw nmap stdout (first 500 chars): {nmap_stdout[:500]}\n") # Print partial raw stdout for debugging
                sys.stderr.flush()
                return []

            # Extract the XML portion
            xml_content = nmap_stdout[xml_start_index:]

            # Parse the XML string
            root = ET.fromstring(xml_content)

            # Process the scan results to extract device info
            discovered_devices = []
            # Iterate through each 'host' element in the XML
            for host_elem in root.findall('.//host'):
                # Check host status - only process hosts that are 'up'
                status_elem = host_elem.find('status')
                if status_elem is None or status_elem.get('state') != 'up':
                    # Get IP for logging purposes even if down/skipped
                    ip_for_log = "unknown IP"
                    address_elem_ip = host_elem.find("./address[@addrtype='ipv4']")
                    if address_elem_ip is not None:
                        ip_for_log = address_elem_ip.get('addr', "unknown IP")
                    sys.stderr.write(f"Skipping host {ip_for_log} (status is not 'up').\n")
                    sys.stderr.flush()
                    continue # Skip hosts that are not reported as 'up'

                ip_address = None
                mac_address = None
                vendor = None
                hostnames = []
                open_ports = [] # Initialize list for open ports

                # Extract addresses (IPv4 and MAC)
                for address_elem in host_elem.findall('address'):
                    addr_type = address_elem.get('addrtype')
                    if addr_type == 'ipv4':
                        ip_address = address_elem.get('addr')
                    elif addr_type == 'mac':
                        mac_address = address_elem.get('addr')
                        vendor = address_elem.get('vendor') # Get vendor attribute if present

                if not ip_address:
                    # Fallback to IPv6 if no IPv4 found (less common for simple LAN devices)
                    address_elem_ipv6 = host_elem.find("./address[@addrtype='ipv6']")
                    if address_elem_ipv6 is not None:
                        ip_address = address_elem_ipv6.get('addr')

                if not ip_address:
                    sys.stderr.write("Skipping host element, could not find IP address.\n")
                    sys.stderr.flush()
                    continue # Skip if no IP address found

                # Extract hostnames
                hostnames_elem = host_elem.find('hostnames')
                if hostnames_elem is not None:
                    for hostname_elem in hostnames_elem.findall('hostname'):
                        hostname = hostname_elem.get('name')
                        if hostname:
                            hostnames.append(hostname)

                # Extract open ports
                ports_elem = host_elem.find('ports')
                if ports_elem is not None:
                    for port_elem in ports_elem.findall('port'):
                        state_elem = port_elem.find('state')
                        # Check if the port state is 'open'
                        if state_elem is not None and state_elem.get('state') == 'open':
                            port_id = port_elem.get('portid')
                            if port_id is not None:
                                try:
                                    # Add the open port number to the list
                                    open_ports.append(int(port_id))
                                except ValueError:
                                    sys.stderr.write(f"Warning: Could not convert port ID '{port_id}' to integer for IP {ip_address}.\n")
                                    sys.stderr.flush()
                                    pass # Skip if port ID is not a valid integer

               device_name = hostnames[0] if hostnames else ip_address

                device_data = {
                    "name": device_name,
                    "ip": ip_address,
                    "mac": mac_address if mac_address else "N/A", # Include MAC or "N/A"
                    "vendor": vendor if vendor else "N/A",       # Include Vendor or "N/A"
                    "open_ports": sorted(open_ports)             # Include sorted list of open ports
                }
                discovered_devices.append(device_data)
                sys.stderr.write(f"Found device: {device_name} ({ip_address}) MAC: {device_data['mac']} Vendor: {device_data['vendor']} Open Ports: {device_data['open_ports']}\n")
                sys.stderr.flush()

            return discovered_devices

        except ET.ParseError as e:
            sys.stderr.write(f"Failed to parse nmap XML output from stdout: {e}\n")
            sys.stderr.write(f"Raw nmap stdout (first 500 chars): {nmap_stdout[:500]}\n") # Print partial raw stdout for debugging XML parsing
            sys.stderr.flush()
            return []
        except Exception as e:
            sys.stderr.write(f"An error occurred while processing nmap XML output: {e}\n")
            sys.stderr.flush()
            return []

    except FileNotFoundError:
        sys.stderr.write(f"Error: nmap executable not found at {NMAP_EXECUTABLE_PATH}\n")
        sys.stderr.write("Please ensure the NMAP_EXECUTABLE_PATH is correct.\n")
        sys.stderr.flush()
        return []
    except Exception as e:
        sys.stderr.write(f"An error occurred during nmap execution: {e}\n")
        sys.stderr.flush()
        return []


if __name__ == "__main__":
    sys.stderr.write("Python script starting network scan (including ports)...\n")
    sys.stderr.flush()

    # Call the updated function name and pass the ports
    discovered_devices = scan_network_details(NETWORK_RANGE, COMMON_PORTS)

    # Output each discovered device as a JSON string on a new line to stdout
    for device in discovered_devices:
        sys.stdout.write(json.dumps(device) + '\n')
        sys.stdout.flush() # Ensure the data is sent immediately

    # Signal the end of discovery on stdout
    sys.stdout.write("DISCOVERY_COMPLETE\n")
    sys.stdout.flush()

    sys.stderr.write(f"Python script finished discovery. Found {len(discovered_devices)} devices.\n")
    sys.stderr.flush()

    # Exit after completion
    sys.exit(0)
