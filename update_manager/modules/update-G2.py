import urllib.error
max_attempts = 3
for attempt in range(max_attempts):
    try:
        # Git subprocess...
        break
    except (subprocess.CalledProcessError, urllib.error.URLError) as e:
        if attempt < max_attempts - 1:
            print_warning(f"Retry {attempt+1}: {str(e)}")
            time.sleep(2)
        else:
            print_error(f"Failed: {str(e)}")