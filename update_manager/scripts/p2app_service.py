# p2app_service.py

# Version: 1.0

# Written by: Jerry DeLong

# Date: July 31, 2025

# Usage: Start: ./p2app_service.py --start Stop: ./p2app_service.py --stop Status: ./p2app_service.py --status

import argparse

import subprocess

import sys

import re

# Color codes
class Colors:
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ORANGE = '\033[38;5;208m'  # Changed from blue to orange
    END = '\033[0m'

def colorize(text, color):
    return f"{color}{text}{Colors.END}"

def colorize_status(output):
    # Colorize important parts
    output = re.sub(r'(running)', colorize(r'\1', Colors.GREEN), output)
    output = re.sub(r'(enabled)', colorize(r'\1', Colors.GREEN), output)
    output = re.sub(r'(inactive)', colorize(r'\1', Colors.YELLOW), output)
    output = re.sub(r'(failed)', colorize(r'\1', Colors.RED), output)
    output = re.sub(r'(preset: enabled)', colorize(r'\1', Colors.GREEN), output)
    # Highlight Main PID in orange (informational)
    output = re.sub(r'(Main PID:\s*\d+)', colorize(r'\1', Colors.ORANGE), output)
    return output

def main():
    parser = argparse.ArgumentParser(description="Manage the p2app.service using systemctl.")
    # Mutually exclusive group to ensure only one action is selected
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--start', action='store_true', help='Start the service')
    group.add_argument('--stop', action='store_true', help='Stop the service')
    group.add_argument('--status', action='store_true', help='Check the status of the service')
    args = parser.parse_args()

    service_name = 'p2app.service'

    if args.start:
        action = 'start'
    elif args.stop:
        action = 'stop'
    elif args.status:
        action = 'status'

    print(colorize(f"Executing '{action}' on {service_name}...", Colors.ORANGE))

    try:
        # Run the systemctl command with sudo
        result = subprocess.run(['sudo', 'systemctl', action, service_name],
                                capture_output=True, text=True, check=True)
        # Print output if any (useful for status)
        if result.stdout:
            if args.status:
                # Colorize important information in status output
                colored_output = colorize_status(result.stdout)
                print(colored_output)
            else:
                print(result.stdout)
        if result.stderr:
            print(colorize(result.stderr, Colors.RED), file=sys.stderr)
        print(colorize(f"Command '{action}' executed successfully.", Colors.GREEN))
    except subprocess.CalledProcessError as e:
        print(colorize(f"Error executing '{action}' on {service_name}: {e}", Colors.RED), file=sys.stderr)
        print(colorize(e.output, Colors.RED), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
