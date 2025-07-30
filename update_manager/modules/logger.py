# modules/logger.py
import logging
from pathlib import Path
from datetime import datetime
import sys

def setup_logging(verbose, log_dir):
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"setup_saturn_webserver-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )
    return logging.getLogger(__name__)
