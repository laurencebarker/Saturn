# modules/verify_executables.py
import os
import shutil
from pathlib import Path
import itertools  # Added for chain

def verify_executables(logger, directories, dry_run):
    """
    Scans the specified directories for .py and .sh files and ensures they are executable.
    Logs warnings for non-executable files and sets permissions if not in dry_run mode.
    Args:
        logger: Logger object for logging messages.
        directories: List of Path objects to scan.
        dry_run: Boolean, if True, simulates the action without changing permissions.
    """
    runtime_dir = Path('/home/pi') / ".saturn/runtime/scripts"  # Fixed to pi user path

    # Copy to runtime before verifying
    runtime_dir.mkdir(parents=True, exist_ok=True)
    for dir_path in directories:
        if not dir_path.exists():
            logger.warning(f"Directory not found: {dir_path}")
            continue
        logger.info(f"Copying files from {dir_path} to runtime {runtime_dir}")
        for file in itertools.chain(dir_path.glob('**/*.py'), dir_path.glob('**/*.sh')):  # Use chain for generators
            relative_path = file.relative_to(dir_path)
            dest_file = runtime_dir / relative_path
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            if dry_run:
                logger.info(f"[Dry Run] Would copy {file} to {dest_file}")
            else:
                shutil.copy2(file, dest_file)  # Preserve metadata/permissions
                logger.info(f"Copied {file} to {dest_file}")

    # Verify in runtime dir only
    logger.info(f"Verifying executables in {runtime_dir}")
    for file in itertools.chain(runtime_dir.glob('**/*.py'), runtime_dir.glob('**/*.sh')):  # Use chain again
        if not os.access(file, os.X_OK):
            if dry_run:
                logger.info(f"[Dry Run] Would set executable on {file}")
            else:
                os.chmod(file, 0o755)
                logger.info(f"Set executable on {file}")

    logger.info("Executable verification complete")
