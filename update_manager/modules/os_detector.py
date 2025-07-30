# modules/os_detector.py
import sys

def detect_os(logger, force_buster):
    if force_buster:
        logger.info("Forced Buster mode")
        return True
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if "PRETTY_NAME" in line:
                    os_version = line.split("=")[1].strip().strip('"').lower()
                    is_buster = "buster" in os_version
                    logger.info(f"Detected OS: {'Buster' if is_buster else 'Bookworm'}")
                    return is_buster
        logger.error("OS detection failed")
        sys.exit(1)
    except Exception as e:
        logger.error(f"OS detection failed: {str(e)}")
        sys.exit(1)
