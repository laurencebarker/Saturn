# modules/migrate_scripts.py
import os
from pathlib import Path
from datetime import datetime
import shutil

def migrate_old_scripts(logger, user_home, dry_run):
    old_scripts_dir = user_home / "scripts"
    config_dir = user_home / ".saturn"
    if not old_scripts_dir.exists():
        logger.info("Old ~/scripts directory does not exist, skipping migration")
        return

    logger.info("Old ~/scripts directory found, starting migration")
    if dry_run:
        logger.info("[Dry Run] Skipping migration")
        return

    # Ensure ~/.saturn exists
    config_dir.mkdir(parents=True, exist_ok=True)

    # Timestamp for backups
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    # Migrate *.json files
    json_files = list(old_scripts_dir.glob("*.json"))
    if not json_files:
        logger.info("No *.json files found in ~/scripts, nothing to migrate")
    else:
        for json_file in json_files:
            dest_file = config_dir / f"{timestamp}-{json_file.name}"
            shutil.copy(json_file, dest_file)
            logger.info(f"Migrated {json_file.name} to {dest_file}")

    # Remove old ~/scripts directory
    shutil.rmtree(old_scripts_dir)
    logger.info("Old ~/scripts directory removed")
    logger.info("Migration complete")