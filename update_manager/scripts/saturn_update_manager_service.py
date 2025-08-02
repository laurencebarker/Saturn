# saturn_update_manager_service.py
# Version: 1.2
# Written by: Jerry DeLong, kd4yal
# Date: Aug 1, 2025
# Changes: Improved handling for negative return codes (signals like -15/SIGTERM) as success for --restart (fixes webapp self-interrupt),
#          added debug print for return codes,
#          original version 1.0 with start/stop/status/restart.

# Usage: Start: ./saturn_update_manager_service.py --start Stop: ./saturn_update_manager_service.py --stop Status: ./saturn_update_manager_service.py --status Restart: ./saturn_update_manager_service.py --restart

import argparse
import subprocess
import sys
import re

COLOR_GREEN = '\033[92m'

COLOR_ORANGE = '\033[38;5;208m'

COLOR_RESET = '\033[0m'

def main():

    parser = argparse.ArgumentParser(description="Manage the saturn-update-manager service using systemctl.")

    # Mutually exclusive group to ensure only one action is selected

    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument('--start', action='store_true', help='Start the service')

    group.add_argument('--stop', action='store_true', help='Stop the service')

    group.add_argument('--status', action='store_true', help='Check the status of the service')

    group.add_argument('--restart', action='store_true', help='Restart the service')

    args = parser.parse_args()

    service_name = 'saturn-update-manager'

    if args.start:

        action = 'start'

    elif args.stop:

        action = 'stop'

    elif args.status:

        action = 'status'

    elif args.restart:

        action = 'restart'

    try:

        # Run the systemctl command with sudo

        result = subprocess.run(['sudo', 'systemctl', action, service_name],

                                capture_output=True, text=True)

        # For restart, treat negative return codes (signals) as success since service self-terminates

        if args.restart and result.returncode < 0:

            print(f"Debug: Return code {result.returncode} (signal) detected - treating as success for restart.")

            result.check_returncode = lambda: None  # Override to skip raise

        result.check_returncode()  # Raise if non-zero (except handled cases)

        # Print output if any (useful for status)

        if result.stdout:

            if action == 'status':

                lines = result.stdout.splitlines()

                for i, line in enumerate(lines):

                    # Colorize service name line

                    if line.startswith('●'):

                        # Find the position after the service name

                        match = re.search(r'● (.+?)( -|$)', line)

                        if match:

                            service_part = match.group(1)

                            line = line.replace(service_part, f'{COLOR_ORANGE}{service_part}{COLOR_RESET}')

                    # Colorize Loaded line

                    if 'Loaded:' in line:

                        line = line.replace('enabled;', f'{COLOR_GREEN}enabled;{COLOR_RESET}')

                        line = line.replace('preset: enabled', f'{COLOR_GREEN}preset: enabled{COLOR_RESET}')

                    # Colorize Active line

                    if 'Active:' in line:

                        line = line.replace('(running)', f'{COLOR_GREEN}(running){COLOR_RESET}')

                    # Colorize Main PID line

                    if 'Main PID:' in line:

                        line = line.replace('Main PID:', f'{COLOR_ORANGE}Main PID:{COLOR_RESET}')

                        match = re.search(r'Main PID: (\d+)', line)

                        if match:

                            pid = match.group(1)

                            line = line.replace(pid, f'{COLOR_GREEN}{pid}{COLOR_RESET}')

                    lines[i] = line

                print('\n'.join(lines))

            else:

                print(result.stdout)

        if result.stderr:

            print(result.stderr, file=sys.stderr)

        print(f"Command '{action}' executed successfully.")

    except subprocess.CalledProcessError as e:

        print(f"Error executing '{action}' on {service_name}: {e}", file=sys.stderr)

        print(e.output, file=sys.stderr)

        sys.exit(1)

if __name__ == '__main__':

    main()
