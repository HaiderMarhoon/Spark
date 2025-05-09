import sys
import time
import json
import subprocess
import platform
import os
import xml.etree.ElementTree as ET # Import the XML parsing library

# This script performs actual LAN device discovery and port scanning using nmap.
# It runs nmap with XML output to stdout, captures and processes this output,
# and outputs simplified JSON for each discovered device to its own stdout,
# along with a completion signal.
# Informational and error messages from nmap and this script are sent to stderr.

# IMPORTANT: This script requires 'nmap' to be installed.
# You need to provide the ABSOLUTE PATH to the nmap executable below.
# Replace "C:\\Program Files (x86)\\Nmap\\nmap.exe" with your actual nmap path.
# You can find your nmap path by typing 'where nmap' in Command Prompt.
NMAP_EXECUTABLE_PATH = "C:\\Program Files (x86)\\Nmap\\nmap.exe" # <-- CONFIGURED WITH USER'S NMAP PATH

# Define the network range to scan. You might need to adjust this based on your network.
# Based on the user's ipconfig, the correct range is 192.168.0.0/24
NETWORK_RANGE = "192.168.0.0/24" # <-- ADJUSTED TO USER'S NETWORK RANGE
# Define a list of common ports to scan. You can expand this list.
COMMON_PORTS = "22,80,443,8080,8000,3389" # Example common ports

def scan_network_with_nmap(network_range, ports):
    """
    Scans the network range using nmap with XML output to stdout,
    captures and processes this output, and yields simplified device dictionaries.
    Sends informational messages and nmap's stderr to the script's stderr.
    """
    sys.stderr.write(f"Python script: Starting nmap scan on {network_range} for ports {ports}...\n")
    sys.stderr.flush()

    # Command to run nmap:
    # -p: Ports to scan
    # -sV: Service version detection
    # -T4: Set timing template (4 is aggressive, adjust if needed)
    # --noninteractive: Disable runtime interactions
    # --system-dns: Use system DNS resolver
    # -oX -: Output in XML format to stdout (nmap's stdout)
    # <network_range>: The target network range

    # Construct the nmap command using the absolute path
    nmap_command = [
        NMAP_EXECUTABLE_PATH, # Use the absolute path
        "-p", ports,
        "-sV", # Service version detection
        "-T4", # Aggressive timing
        "--noninteractive",
        "--system-dns",
        "-oX", "-", # Output XML to nmap's stdout
        network_range
    ]

    sys.stderr.write(f"Executing command: {' '.join(nmap_command)}\n")
    sys.stderr.flush()

    try:
        # Check if the nmap executable exists at the specified path
        if not os.path.exists(NMAP_EXECUTABLE_PATH):
            sys.stderr.write(f"Error: nmap executable not found at {NMAP_EXECUTABLE_PATH}\n")
            sys.stderr.write("Please update NMAP_EXECUTABLE_PATH in the script with the correct path.\n")
            sys.stderr.flush()
            return [] # Return empty list on error

        # Execute the nmap command
        # Capture nmap's stdout (which should be XML due to -oX -)
        # Capture nmap's stderr (for its progress and error messages)
        process = subprocess.Popen(
            nmap_command,
            stdout=subprocess.PIPE, # Capture nmap's stdout
            stderr=subprocess.PIPE, # Capture nmap's stderr
            text=True, # Decode streams as text
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
            return [] # Return empty list on error

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
                sys.stderr.write(f"Raw nmap stdout: {nmap_stdout}\n") # Print raw stdout for debugging
                sys.stderr.flush()
                return []

            # Extract the XML portion
            xml_content = nmap_stdout[xml_start_index:]

            # Parse the XML string
            root = ET.fromstring(xml_content)

            # Process the scan results to extract device info and open ports
            discovered_devices = []
            # Iterate through each 'host' element in the XML
            for host_elem in root.findall('.//host'):
                # Check host status
                status_elem = host_elem.find('status')
                if status_elem is not None and status_elem.get('state') == 'down':
                    continue # Skip hosts that are reported as 'down'

                ip_address = None
                hostnames = []
                open_ports = []

                # Extract IP address(es)
                for address_elem in host_elem.findall('address'):
                    if address_elem.get('addrtype') == 'ipv4':
                        ip_address = address_elem.get('addr')
                        break # Assuming we only need the IPv4 address for now

                if not ip_address:
                    continue # Skip if no IPv4 address found

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
                        # Check port state
                        state_elem = port_elem.find('state')
                        if state_elem is not None and state_elem.get('state') == 'open':
                            port_id = port_elem.get('portid')
                            if port_id is not None:
                                try:
                                    open_ports.append(int(port_id)) # Convert port ID to integer
                                except ValueError:
                                    sys.stderr.write(f"Warning: Could not convert port ID '{port_id}' to integer.\n")
                                    sys.stderr.flush()
                                    pass # Skip if port ID is not a valid integer


                # Determine device name (prefer hostname, fallback to IP)
                device_name = hostnames[0] if hostnames else ip_address

                # Create a simplified dictionary for the discovered device
                device_data = {
                    "name": device_name,
                    "ip": ip_address, # Include IP in the output JSON
                    "open_ports": open_ports
                    # You could add more info here like MAC address, OS if nmap detected it
                }
                discovered_devices.append(device_data)

            return discovered_devices

        except ET.ParseError as e:
            sys.stderr.write(f"Failed to parse nmap XML output from stdout: {e}\n")
            sys.stderr.write(f"Raw nmap stdout: {nmap_stdout}\n") # Print raw stdout for debugging XML parsing
            sys.stderr.flush()
            return []
        except Exception as e:
            sys.stderr.write(f"An error occurred while processing nmap XML output: {e}\n")
            sys.stderr.flush()
            return []

    except FileNotFoundError:
        # This specific FileNotFoundError should ideally not happen if the os.path.exists check works,
        # but keeping it as a fallback.
        sys.stderr.write(f"Error: nmap executable not found at {NMAP_EXECUTABLE_PATH}\n")
        sys.stderr.write("Please ensure the NMAP_EXECUTABLE_PATH is correct.\n")
        sys.stderr.flush()
        return []
    except Exception as e:
        sys.stderr.write(f"An error occurred during nmap execution: {e}\n")
        sys.stderr.flush()
        return []


if __name__ == "__main__":
    sys.stderr.write("Python script waiting for command or starting default scan...\n")
    sys.stderr.flush()

    # For this version, we'll run the scan directly on startup.
    # In a more complex IPC scenario, you might wait for a 'start_scan' command from stdin.

    discovered_devices = scan_network_with_nmap(NETWORK_RANGE, COMMON_PORTS)

    # Output each discovered device as a JSON string on a new line to stdout
    for device in discovered_devices:
        sys.stdout.write(json.dumps(device) + '\n')
        sys.stdout.flush() # Ensure the data is sent immediately

    # Signal the end of discovery on stdout
    sys.stdout.write("DISCOVERY_COMPLETE\n")
    sys.stdout.flush()

    sys.stderr.write("Python script finished discovery and port scanning.\n")
    sys.stderr.flush()

    # Keep the script running briefly to ensure output is processed
    # In a real application, you might keep it running to receive more commands
    # time.sleep(1) # Optional: small delay before exiting
    # sys.exit(0) # Explicitly exit after completion if not expecting more commands

    # If you uncomment the command reading loop later, remove the sys.exit(0)
    # while True:
    #     try:
    #         line = sys.stdin.readline().strip()
    #         if not line:
    #             # End of input, exit
    #             break
    #         sys.stderr.write(f"Received command: {line}\n")
    #         sys.stderr.flush()
    #         if line == "start_discovery":
    #             discovered_devices = scan_network_with_nmap(NETWORK_RANGE, COMMON_PORTS)
    #             for device in discovered_devices:
    #                 sys.stdout.write(json.dumps(device) + '\n')
    #                 sys.stdout.flush()
    #             sys.stdout.write("DISCOVERY_COMPLETE\n")
    #             sys.stdout.flush()
    #         elif line == "exit":
    #             break
    #         # Add other commands as needed
    #     except EOFError:
    #         # stdin is closed
    #         break
    #     except Exception as e:
    #         sys.stderr.write(f"Python script error: {e}\n")
    #         sys.stderr.flush()

    sys.stderr.write("Python script exiting.\n")
    sys.stderr.flush()
