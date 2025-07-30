# modules/logger.py
import logging
from pathlib import Path
from datetime import datetime
import sys

class FlushHandler(logging.StreamHandler):
    def emit(self, record):
        super().emit(record)
        self.flush()  # Force flush for CLI visibility

def setup_logging(verbose, log_dir):
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"setup_saturn_webserver-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file),
            FlushHandler(sys.stdout)
        ]
    )
    return logging.getLogger(__name__)
