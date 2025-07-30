# modules/verify_executables.py
import os
from pathlib import Path

def verify_executables(logger, directories, dry_run):
    """
    Scans the specified directories for .py and .sh files and ensures they are executable.
    Logs warnings for non-executable files and sets permissions if not in dry_run mode.

    Args:
        logger: Logger object for logging messages.
        directories: List of Path objects to scan.
        dry_run: Boolean, if True, simulates the action without changing permissions.
    """
    for dir_path in directories:
        if not dir_path.exists():
            logger.warning(f"Directory not found: {dir_path}")
            continue
        logger.info(f"Verifying executables in {dir_path}")
        for file in dir_path.glob('**/*.py'):
            if not os.access(file, os.X_OK):
                if dry_run:
                    logger.info(f"[Dry Run] Would set executable on {file}")
                else:
                    os.chmod(file, 0o755)
                    logger.info(f"Set executable on {file}")
        for file in dir_path.glob('**/*.sh'):
            if not os.access(file, os.X_OK):
                if dry_run:
                    logger.info(f"[Dry Run] Would set executable on {file}")
                else:
                    os.chmod(file, 0o755)
                    logger.info(f"Set executable on {file}")
    logger.info("Executable verification complete")