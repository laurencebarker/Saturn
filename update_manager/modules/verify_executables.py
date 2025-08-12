# modules/verify_executables.py
import os
import shutil
from pathlib import Path
import itertools  # Added for chain
import pwd

def verify_executables(logger, directories, dry_run, user_home, username):
    """
    Copies .py and .sh files into the user's runtime dir and ensures they are executable & owned by the user.

    Args:
        logger: Logger object for logging messages.
        directories: List of Path objects to scan & copy from.
        dry_run: Boolean, if True, simulates the action without changing files.
        user_home: Path to the target user's home directory.
        username: Target username for ownership.
    """
    try:
        pw = pwd.getpwnam(username)
        uid = pw.pw_uid
        gid = pw.pw_gid
    except KeyError:
        logger.warning(f"User '{username}' not found; skipping ownership adjustments.")
        uid = gid = None

    runtime_dir = user_home / ".saturn" / "runtime" / "scripts"

    # Copy to runtime before verifying
    runtime_dir.mkdir(parents=True, exist_ok=True)
    if uid is not None:
        try:
            os.chown(runtime_dir, uid, gid)
        except PermissionError:
            logger.warning(f"Insufficient privileges to chown {runtime_dir}")

    for dir_path in directories:
        if not dir_path.exists():
            logger.warning(f"Directory not found: {dir_path}")
            continue
        logger.info(f"Copying files from {dir_path} to runtime {runtime_dir}")
        for file in itertools.chain(dir_path.glob('**/*.py'), dir_path.glob('**/*.sh')):
            try:
                relative_path = file.relative_to(dir_path)
            except ValueError:
                # If not under dir_path (shouldn't happen), flatten
                relative_path = file.name
            dest_file = runtime_dir / relative_path
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            if dry_run:
                logger.info(f"[Dry Run] Would copy {file} to {dest_file}")
            else:
                shutil.copy2(file, dest_file)  # Preserve metadata/permissions
                if uid is not None:
                    try:
                        # Ensure ownership of file and its parent dir
                        os.chown(dest_file, uid, gid)
                        os.chown(dest_file.parent, uid, gid)
                    except PermissionError:
                        logger.warning(f"Insufficient privileges to chown {dest_file}")
                logger.info(f"Copied {file} to {dest_file}")

    # Verify in runtime dir only
    logger.info(f"Verifying executables in {runtime_dir}")
    for file in itertools.chain(runtime_dir.glob('**/*.py'), runtime_dir.glob('**/*.sh')):
        if not os.access(file, os.X_OK):
            if dry_run:
                logger.info(f"[Dry Run] Would set executable on {file}")
            else:
                os.chmod(file, 0o755)
                logger.info(f"Set executable on {file}")

    logger.info("Executable verification complete")
