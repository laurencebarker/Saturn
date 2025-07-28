#!/bin/bash
# create_files.sh - Creates index.html, saturn_update_manager.py, config.json, themes.json, and SaturnUpdateManager.desktop
# Version: 2.0
# Written by: Jerry DeLong KD4YAL
# Dependencies: bash
# Usage: Called by setup_saturn_webserver.sh

set -e

# Paths
SCRIPTS_DIR="/home/pi/scripts"
TEMPLATES_DIR="$SCRIPTS_DIR/templates"
LOG_DIR="/home/pi/saturn-logs"
DESKTOP_FILE="$SCRIPTS_DIR/SaturnUpdateManager.desktop"
DESKTOP_DEST="/home/pi/Desktop/SaturnUpdateManager.desktop"
SATURN_SCRIPT="$SCRIPTS_DIR/saturn_update_manager.py"
INDEX_HTML="$TEMPLATES_DIR/index.html"
CONFIG_JSON="$SCRIPTS_DIR/config.json"
THEMES_JSON="$SCRIPTS_DIR/themes.json"
LOG_CLEANER_SCRIPT="$SCRIPTS_DIR/log_cleaner.sh"
RESTORE_SCRIPT="$SCRIPTS_DIR/restore-backup.sh"
LOG_FILE="$LOG_DIR/setup_saturn_webserver-$(date +%Y%m%d-%H%M%S).log"
VENV_PATH="/home/pi/venv"
OLD_SCRIPTS_DIR="/home/pi/github/Saturn/Update-webserver-setup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to log and echo output
log_and_echo() {
    echo -e "$1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Create directories
log_and_echo "${CYAN}Creating directories...${NC}"
mkdir -p "$SCRIPTS_DIR" "$TEMPLATES_DIR" "$LOG_DIR" "/home/pi/Desktop"
chmod -R u+rwX "$SCRIPTS_DIR" "$TEMPLATES_DIR" "$LOG_DIR" "/home/pi/Desktop"
chown pi:pi "$LOG_DIR" "$TEMPLATES_DIR" "/home/pi/Desktop"
chmod 775 "$LOG_DIR" "/home/pi/Desktop" "$SCRIPTS_DIR"
log_and_echo "${GREEN}Directories created${NC}"

# Move update scripts if they exist in old location
log_and_echo "${CYAN}Checking for update scripts in old location and moving if necessary...${NC}"
for script in "update-G2.py" "update-pihpsdr.py"; do
    if [ -f "$OLD_SCRIPTS_DIR/$script" ] && [ ! -f "$SCRIPTS_DIR/$script" ]; then
        cp "$OLD_SCRIPTS_DIR/$script" "$SCRIPTS_DIR/"
        chmod +x "$SCRIPTS_DIR/$script"
        chown pi:pi "$SCRIPTS_DIR/$script"
        log_and_echo "${GREEN}Moved $script to $SCRIPTS_DIR${NC}"
    fi
done

# Create config.json (back up if exists)
log_and_echo "${CYAN}Creating config.json in $SCRIPTS_DIR...${NC}"
if [ -f "$CONFIG_JSON" ]; then
    BACKUP_FILE="${CONFIG_JSON}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_JSON" "$BACKUP_FILE"
    log_and_echo "${GREEN}Backed up existing config.json to $BACKUP_FILE${NC}"
fi
cat > "$CONFIG_JSON" << 'EOF'
[
  {
    "filename": "update-G2.py",
    "name": "Update G2",
    "description": "Updates Saturn G2 component",
    "directory": "~/scripts",
    "category": "Update Scripts",
    "flags": ["--skip-git", "-y", "-n", "--dry-run", "--verbose"]
  },
  {
    "filename": "update-pihpsdr.py",
    "name": "Update piHPSDR",
    "description": "Updates piHPSDR component",
    "directory": "~/scripts",
    "category": "Update Scripts",
    "flags": ["--skip-git", "-y", "-n", "--no-gpio", "--dry-run", "--verbose"]
  },
  {
    "filename": "log_cleaner.sh",
    "name": "Log Cleaner",
    "description": "Searches for *.log files, reports space usage, and optionally deletes them",
    "directory": "~/scripts",
    "category": "Maintenance",
    "flags": ["--delete-all", "--no-recursive", "--dry-run"]
  },
  {
    "filename": "restore-backup.sh",
    "name": "Restore Backup",
    "description": "Restores from a previous Saturn or piHPSDR backup directory",
    "directory": "~/scripts",
    "category": "Maintenance",
    "flags": ["--pihpsdr", "--saturn", "--latest", "--list", "--dry-run", "--verbose"]
  }
]
EOF
chmod 644 "$CONFIG_JSON"
chown pi:pi "$CONFIG_JSON"
log_and_echo "${GREEN}config.json created (or updated with backup if existed)${NC}"

# Create themes.json if not exists
log_and_echo "${CYAN}Creating themes.json in $SCRIPTS_DIR (overwriting if exists)...${NC}"
rm -f "$THEMES_JSON"
cat > "$THEMES_JSON" << 'EOF'
[
  {
    "name": "Default",
    "description": "Standard light theme",
    "styles": {
      "--bg-color": "#f3f4f6",
      "--text-color": "#333333",
      "--primary-color": "#3b82f6",
      "--secondary-color": "#10b981",
      "--card-bg": "#ffffff"
    }
  },
  {
    "name": "Dark Mode",
    "description": "Dark theme for low-light environments",
    "styles": {
      "--bg-color": "#1a1a1a",
      "--text-color": "#ffffff",
      "--primary-color": "#60a5fa",
      "--secondary-color": "#34d399",
      "--card-bg": "#333333"
    }
  },
  {
    "name": "High Contrast",
    "description": "High contrast theme for accessibility",
    "styles": {
      "--bg-color": "#ffffff",
      "--text-color": "#000000",
      "--primary-color": "#0000ff",
      "--secondary-color": "#008000",
      "--card-bg": "#ffffff"
    }
  }
]
EOF
chmod 644 "$THEMES_JSON"
chown pi:pi "$THEMES_JSON"
log_and_echo "${GREEN}themes.json created with example entries${NC}"

# Create index.html
log_and_echo "${CYAN}Creating index.html in $TEMPLATES_DIR (overwriting if exists)...${NC}"
rm -f "$INDEX_HTML"
cat > "$INDEX_HTML" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Saturn Update Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        :root {
            --bg-color: #f3f4f6;
            --text-color: #333333;
            --primary-color: #3b82f6;
            --secondary-color: #10b981;
            --card-bg: #ffffff;
        }
        body {
            background-color: var(--bg-color);
            color: var(--text-color);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        .btn-primary {
            background-color: var(--primary-color);
        }
        .btn-secondary {
            background-color: var(--secondary-color);
        }
        pre {
            white-space: pre-wrap;
            word-wrap: break-word;
            font-family: 'Courier New', monospace;
            background-color: #1a1a1a;
            color: #ffffff;
            padding: 1rem;
            overflow-y: auto;
            min-height: 400px;
            max-height: 500px;
            line-height: 1.4;
            margin: 0;
            border: 1px solid #444;
            box-sizing: border-box;
        }
        .output-container {
            width: 100%;
            min-height: 420px;
            background-color: #1a1a1a;
            padding: 0;
            border-radius: 0.5rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .container { max-width: 800px; }
        .ansi_31 { color: #ff5555 !important; }
        .ansi_32 { color: #55ff55 !important; }
        .ansi_33 { color: #ffff55 !important; }
        .ansi_34 { color: #5555ff !important; }
        .ansi_36 { color: #55ffff !important; }
        /* Spinner for loading */
        .spinner {
            border: 4px solid rgba(0, 0, 0, 0.1);
            border-left-color: var(--primary-color);
            border-radius: 50%;
            width: 24px;
            height: 24px;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        /* Progress bar styling */
        progress {
            width: 100%;
            height: 20px;
            appearance: none;
            border: none;
            background-color: #e5e7eb;
            border-radius: 0.25rem;
        }
        progress::-webkit-progress-bar {
            background-color: #e5e7eb;
            border-radius: 0.25rem;
        }
        progress::-webkit-progress-value {
            background-color: var(--primary-color);
            border-radius: 0.25rem;
        }
        progress::-moz-progress-bar {
            background-color: var(--primary-color);
            border-radius: 0.25rem;
        }
        /* Mobile adjustments */
        @media (max-width: 640px) {
            .container { padding: 1rem; }
            button { padding: 0.75rem 1.5rem; font-size: 1.125rem; }
            select, input { font-size: 1rem; padding: 0.5rem; }
        }
    </style>
</head>
<body>
    <div class="container mx-auto p-4 sm:p-6">
        <h1 class="text-3xl font-bold text-red-600 text-center mb-2">Saturn Update Manager</h1>

        <div id="versions-container" class="rounded-lg shadow-md p-4 mb-4" style="display: none; background-color: var(--card-bg);">
            <h2 class="text-xl font-semibold text-gray-700 mb-2">Script Versions</h2>
            <ul id="version-list" class="list-disc pl-5 text-gray-600"></ul>
        </div>

        <div class="rounded-lg shadow-md p-4 mb-4 relative" style="background-color: var(--card-bg);">
            <!-- Loading Spinner -->
            <div id="loader" class="absolute inset-0 flex items-center justify-center bg-opacity-75 hidden" style="background-color: var(--card-bg);">
                <div class="spinner"></div>
            </div>
            <form id="script-form" class="flex flex-col space-y-4">
                <div class="flex items-center space-x-4">
                    <label for="script" class="text-lg font-medium text-gray-700">Select Script:</label>
                    <select id="script" name="script" class="border rounded px-2 py-1 bg-blue-100 text-blue-800 w-full">
                        <option value="">Select a script</option>
                    </select>
                </div>
                <div id="flags" class="flex flex-wrap gap-4"></div>
                <div id="restore-dir-div" class="flex flex-col space-y-2 hidden">
                    <label for="restore-dir-select" class="text-lg font-medium text-gray-700">Select Backup Directory:</label>
                    <select id="restore-dir-select" class="border rounded px-2 py-1 bg-blue-100 text-blue-800 w-full">
                        <option value="">Select...</option>
                    </select>
                </div>
                <div class="flex justify-center space-x-4">
                    <button type="submit" class="btn-primary text-white px-4 py-2 rounded hover:brightness-90 sm:px-6 sm:py-3">Run</button>
                    <button type="button" id="change-password-btn" class="btn-secondary text-white px-4 py-2 rounded hover:brightness-90 sm:px-6 sm:py-3">Change Password</button>
                    <button type="button" id="exit-btn" class="btn-primary text-white px-4 py-2 rounded hover:brightness-90 sm:px-6 sm:py-3">Exit</button>
                    <label class="flex items-center space-x-2">
                        <input type="checkbox" id="show-versions" class="form-checkbox h-5 w-5 text-blue-600">
                        <span>Show Versions</span>
                    </label>
                </div>
            </form>
        </div>

        <div class="flex flex-col space-y-2 mb-4">
            <label for="theme" class="text-lg font-medium text-gray-700">Select Theme:</label>
            <select id="theme" class="border rounded px-2 py-1 bg-blue-100 text-blue-800 w-full">
                <option value="">Select a theme</option>
            </select>
        </div>

        <div class="output-container">
            <!-- Progress Bar -->
            <progress id="progress" value="0" max="100" class="mb-2 hidden"></progress>
            <pre id="output" class="text-sm"></pre>
        </div>

        <!-- Backup Prompt Modal -->
        <div id="backup-modal" class="hidden fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center">
            <div class="rounded-lg p-6 max-w-sm w-full" style="background-color: var(--card-bg);">
                <h2 class="text-xl font-bold mb-4">Backup Prompt</h2>
                <p class="mb-4">Create a backup? (Y/n)</p>
                <div class="flex justify-end space-x-4">
                    <button id="backup-yes" class="btn-primary text-white px-4 py-2 rounded hover:brightness-90">Yes</button>
                    <button id="backup-no" class="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">No</button>
                </div>
            </div>
        </div>

        <!-- Change Password Modal -->
        <div id="password-modal" class="hidden fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center">
            <div class="rounded-lg p-6 max-w-sm w-full" style="background-color: var(--card-bg);">
                <h2 class="text-xl font-bold mb-4">Change Password</h2>
                <form id="password-form" class="flex flex-col space-y-4">
                    <div>
                        <label for="new-password" class="text-lg font-medium text-gray-700">New Password:</label>
                        <input type="password" id="new-password" name="new-password" class="border rounded px-2 py-1 w-full" required minlength="8">
                    </div>
                    <div>
                        <label for="confirm-password" class="text-lg font-medium text-gray-700">Confirm Password:</label>
                        <input type="password" id="confirm-password" name="confirm-password" class="border rounded px-2 py-1 w-full" required minlength="8">
                    </div>
                    <p id="password-error" class="text-red-500 hidden">Passwords do not match or are too short.</p>
                    <div class="flex justify-end space-x-4">
                        <button type="submit" class="btn-primary text-white px-4 py-2 rounded hover:brightness-90">Submit</button>
                        <button type="button" id="password-cancel" class="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600">Cancel</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script>
        function showLoader(show) {
            document.getElementById('loader').classList.toggle('hidden', !show);
        }

        async function loadVersions() {
            showLoader(true);
            try {
                const response = await fetch('/saturn/get_versions', {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch versions failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Versions response:', data);
                const versionList = document.getElementById('version-list');
                versionList.innerHTML = '';
                if (data.versions) {
                    Object.entries(data.versions).forEach(([script, version]) => {
                        const li = document.createElement('li');
                        li.textContent = `${script}: ${version}`;
                        versionList.appendChild(li);
                    });
                } else {
                    console.warn('No versions returned from /saturn/get_versions');
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: No versions available</span>\n`;
                }
            } catch (error) {
                console.error('Error loading versions:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading versions: ${error.message}</span>\n`;
            } finally {
                showLoader(false);
            }
        }

        async function loadScripts() {
            showLoader(true);
            try {
                const response = await fetch('/saturn/get_scripts', {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch scripts failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Scripts response:', data);
                const scriptSelect = document.getElementById('script');
                scriptSelect.innerHTML = '<option value="">Select a script</option>';
                const output = document.getElementById('output');
                if (data.warnings && data.warnings.length > 0) {
                    output.innerHTML += data.warnings.map(w => `<span style="color:#FFFF00">Warning: ${w}</span>`).join('\n') + '\n';
                }
                if (data.scripts) {
                    if (Array.isArray(data.scripts)) {
                        // Fallback for flat array
                        const optgroup = document.createElement('optgroup');
                        optgroup.label = 'Scripts';
                        data.scripts.forEach(script => {
                            const option = document.createElement('option');
                            option.value = script;
                            option.textContent = script;
                            optgroup.appendChild(option);
                        });
                        scriptSelect.appendChild(optgroup);
                    } else {
                        // Grouped object
                        const categories = Object.keys(data.scripts).sort();
                        categories.forEach(category => {
                            const optgroup = document.createElement('optgroup');
                            optgroup.label = category;
                            data.scripts[category].forEach(script => {
                                const option = document.createElement('option');
                                option.value = script.filename;
                                option.textContent = script.name;
                                option.title = script.description;
                                optgroup.appendChild(option);
                            });
                            scriptSelect.appendChild(optgroup);
                        });
                    }
                    if (scriptSelect.options.length > 1) {
                        scriptSelect.value = scriptSelect.options[1].value;
                        loadFlags(scriptSelect.value);
                    }
                } else {
                    console.warn('No scripts returned from /saturn/get_scripts');
                    output.innerHTML += `<span style="color:#FF0000">Error: No scripts available</span>\n`;
                }
            } catch (error) {
                console.error('Error loading scripts:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading scripts: ${error.message}</span>\n`;
            } finally {
                showLoader(false);
            }
        }

        async function loadFlags(filename) {
            showLoader(true);
            try {
                const response = await fetch(`/saturn/get_flags?script=${encodeURIComponent(filename)}`, {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch flags failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Flags response:', data);
                const flagsDiv = document.getElementById('flags');
                flagsDiv.innerHTML = '';
                if (data.error) {
                    console.error('Error from get_flags:', data.error);
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: ${data.error}</span>\n`;
                    return;
                }
                data.flags.forEach(flag => {
                    const label = document.createElement('label');
                    label.className = 'flex items-center space-x-2';
                    label.innerHTML = `<input type="checkbox" name="flags" value="${flag}" class="form-checkbox h-5 w-5 text-blue-600" ${flag === '--verbose' ? 'checked' : ''}> <span>${flag}</span>`;
                    flagsDiv.appendChild(label);
                });
                console.log(`Loaded flags for ${filename}:`, data.flags);
                if (filename === 'restore-backup.sh') {
                    document.getElementById('restore-dir-div').classList.remove('hidden');
                } else {
                    document.getElementById('restore-dir-div').classList.add('hidden');
                }
            } catch (error) {
                console.error('Error loading flags:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading flags: ${error.message}</span>\n`;
            } finally {
                showLoader(false);
            }
        }

        async function loadThemes() {
            try {
                const response = await fetch('/saturn/get_themes', {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch themes failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Themes response:', data);
                const themeSelect = document.getElementById('theme');
                themeSelect.innerHTML = '<option value="">Select a theme</option>';
                data.themes.forEach(theme => {
                    const option = document.createElement('option');
                    option.value = theme.name;
                    option.textContent = theme.name;
                    option.title = theme.description;
                    themeSelect.appendChild(option);
                });
                if (data.warnings && data.warnings.length > 0) {
                    document.getElementById('output').innerHTML += data.warnings.map(w => `<span style="color:#FFFF00">Warning: ${w}</span>`).join('\n') + '\n';
                }
            } catch (error) {
                console.error('Error loading themes:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading themes: ${error.message}</span>\n`;
            }
        }

        async function applyTheme(name) {
            try {
                const response = await fetch(`/saturn/get_theme?name=${encodeURIComponent(name)}`, {
                    headers: {
                        'Cache-Control': 'no-cache'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Fetch theme failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                const data = await response.json();
                console.log('Theme data:', data);
                if (data.styles) {
                    Object.entries(data.styles).forEach(([key, value]) => {
                        document.documentElement.style.setProperty(key, value);
                    });
                    localStorage.setItem('selectedTheme', name);
                }
            } catch (error) {
                console.error('Error applying theme:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error applying theme: ${error.message}</span>\n`;
            }
        }

        document.getElementById('theme').addEventListener('change', function() {
            const selectedTheme = this.value;
            if (selectedTheme) {
                applyTheme(selectedTheme);
            }
        });

        // Load saved theme on page load
        const savedTheme = localStorage.getItem('selectedTheme');
        if (savedTheme) {
            document.getElementById('theme').value = savedTheme;
            applyTheme(savedTheme);
        }

        document.getElementById('flags').addEventListener('change', async function(e) {
            if (e.target.name === 'flags' && (e.target.value === '--pihpsdr' || e.target.value === '--saturn')) {
                let type = null;
                const pihpsdrChecked = Array.from(document.querySelectorAll('input[name="flags"]')).find(cb => cb.value === '--pihpsdr' ).checked;
                const saturnChecked = Array.from(document.querySelectorAll('input[name="flags"]')).find(cb => cb.value === '--saturn' ).checked;
                if (pihpsdrChecked && saturnChecked) {
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: Cannot select both --pihpsdr and --saturn</span>\n`;
                    return;
                }
                if (pihpsdrChecked) type = 'pihpsdr';
                if (saturnChecked) type = 'saturn';
                if (type) {
                    try {
                        const response = await fetch(`/saturn/get_backups?type=${type}`, {
                            headers: {
                                'Cache-Control': 'no-cache'
                            }
                        });
                        if (!response.ok) {
                            const errorText = await response.text();
                            console.error('Fetch backups failed:', response.status, errorText);
                            throw new Error(`HTTP ${response.status}: ${errorText}`);
                        }
                        const data = await response.json();
                        const select = document.getElementById('restore-dir-select');
                        select.innerHTML = '<option value="">Select...</option>';
                        data.backups.forEach(dir => {
                            const option = document.createElement('option');
                            option.value = dir;
                            option.textContent = dir;
                            select.appendChild(option);
                        });
                    } catch (error) {
                        console.error('Error loading backups:', error);
                        document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error loading backups: ${error.message}</span>\n`;
                    }
                } else {
                    const select = document.getElementById('restore-dir-select');
                    select.innerHTML = '<option value="">Select...</option>';
                }
            }
        });

        document.getElementById('script-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            const filename = document.getElementById('script').value;
            let flags = Array.from(document.querySelectorAll('input[name="flags"]:checked')).map(cb => cb.value);
            const output = document.getElementById('output');
            const progress = document.getElementById('progress');
            output.innerHTML = '';
            progress.classList.remove('hidden');
            progress.value = 0;
            console.log(`Submitting run request for ${filename}, flags:`, flags);

            const restoreDirDiv = document.getElementById('restore-dir-div');
            if (filename === 'restore-backup.sh' && !restoreDirDiv.classList.contains('hidden')) {
                const restoreDir = document.getElementById('restore-dir-select').value;
                if (restoreDir) {
                    flags.push('--backup-dir');
                    flags.push(restoreDir);
                }
            }

            try {
                const formData = new FormData();
                formData.append('script', filename);
                flags.forEach(flag => formData.append('flags', flag));
                const response = await fetch('/saturn/run', {
                    method: 'POST',
                    body: formData,
                    headers: {
                        'Accept': 'text/event-stream'
                    }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Run request failed:', response.status, errorText);
                    throw new Error(`HTTP ${response.status}: ${errorText}`);
                }
                console.log('Run request sent successfully');
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let buffer = '';
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) {
                        console.log('Stream complete');
                        if (buffer) {
                            console.log('Processing buffered data:', buffer);
                            const lines = buffer.split('\n\n');
                            for (const line of lines) {
                                if (line.startsWith('data: ')) {
                                    const data = line.substring(6);
                                    console.log(`Received data: ${data}`);
                                    if (data === 'BACKUP_PROMPT') {
                                        console.log('Received BACKUP_PROMPT');
                                        document.getElementById('backup-modal').classList.remove('hidden');
                                    } else {
                                        output.innerHTML += data + '\n';
                                        console.log(`Appended HTML: ${data}`);
                                        output.scrollTop = output.scrollHeight;
                                        output.style.height = output.scrollHeight + 'px';
                                    }
                                }
                            }
                            buffer = '';
                        }
                        progress.classList.add('hidden');
                        break;
                    }
                    const chunk = decoder.decode(value, { stream: true });
                    console.log('Received chunk:', chunk);
                    buffer += chunk;
                    const lines = buffer.split('\n\n');
                    buffer = lines.pop() || '';
                    for (const line of lines) {
                        if (line.startsWith('data: ')) {
                            const data = line.substring(6);
                            console.log(`Received data: ${data}`);
                            if (data === 'BACKUP_PROMPT') {
                                console.log('Received BACKUP_PROMPT');
                                document.getElementById('backup-modal').classList.remove('hidden');
                            } else {
                                output.innerHTML += data + '\n';
                                console.log(`Appended HTML: ${data}`);
                                output.scrollTop = output.scrollHeight;
                                output.style.height = output.scrollHeight + 'px';
                                // Parse for progress (example: look for "Progress: 50%")
                                const match = data.match(/Progress:\s*(\d+)%/i);
                                if (match) {
                                    progress.value = parseInt(match[1], 10);
                                }
                            }
                        }
                    }
                }
            } catch(error) {
                console.error('Run error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error: ${error.message}</span>\n`;
                progress.classList.add('hidden');
            }
        });

        document.getElementById('script').addEventListener('change', function() {
            console.log('Script changed:', this.value);
            if (this.value) {
                loadFlags(this.value);
            }
        });

        document.getElementById('backup-yes').addEventListener('click', function() {
            console.log('Sending backup response: y');
            fetch('/saturn/backup_response', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'response=y'
            }).then(() => {
                console.log('Backup response sent: y');
                document.getElementById('backup-modal').classList.add('hidden');
            }).catch(error => {
                console.error('Backup yes error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error sending backup response: ${error.message}</span>\n`;
            });
        });

        document.getElementById('backup-no').addEventListener('click', function() {
            console.log('Sending backup response: n');
            fetch('/saturn/backup_response', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'response=n'
            }).then(() => {
                console.log('Backup response sent: n');
                document.getElementById('backup-modal').classList.add('hidden');
            }).catch(error => {
                console.error('Backup no error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error sending backup response: ${error.message}</span>\n`;
            });
        });

        document.getElementById('change-password-btn').addEventListener('click', function() {
            console.log('Opening password change modal');
            document.getElementById('password-modal').classList.remove('hidden');
            document.getElementById('new-password').value = '';
            document.getElementById('confirm-password').value = '';
            document.getElementById('password-error').classList.add('hidden');
        });

        document.getElementById('password-cancel').addEventListener('click', function() {
            console.log('Closing password change modal');
            document.getElementById('password-modal').classList.add('hidden');
        });

        document.getElementById('password-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            const newPassword = document.getElementById('new-password').value;
            const confirmPassword = document.getElementById('confirm-password').value;
            const errorDiv = document.getElementById('password-error');
            if (newPassword !== confirmPassword || newPassword.length < 8) {
                console.error('Password validation failed');
                errorDiv.textContent = 'Passwords do not match or are too short (minimum 8 characters).';
                errorDiv.classList.remove('hidden');
                return;
            }
            try {
                const response = await fetch('/saturn/change_password', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: `new_password=${encodeURIComponent(newPassword)}`
                });
                const data = await response.json();
                if (response.ok && data.status === 'success') {
                    console.log('Password changed successfully');
                    document.getElementById('output').innerHTML += `<span style="color:#00FF00">Password changed successfully</span>\n`;
                    document.getElementById('password-modal').classList.add('hidden');
                } else {
                    throw new Error(data.message || `HTTP ${response.status}`);
                }
            } catch (error) {
                console.error('Error changing password:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error changing password: ${error.message}</span>\n`;
            }
        });

        document.getElementById('exit-btn').addEventListener('click', async function() {
            console.log('Initiating exit and logoff');
            try {
                const response = await fetch('/saturn/exit', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });
                if (!response.ok) {
                    const errorText = await response.text();
                    console.error('Exit request failed:', response.status, errorText);
                    document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error during exit: ${errorText}</span>\n`;
                    return;
                }
                const data = await response.json();
                console.log('Exit response:', data);
                if (data.status === 'shutting down') {
                    console.log('Server shutting down, forcing re-authentication');
                    // Force re-authentication by fetching a protected endpoint with invalid credentials
                    try {
                        await fetch('/saturn/', {
                            headers: {
                                'Authorization': 'Basic invalid_credentials',
                                'Cache-Control': 'no-cache'
                            }
                        });
                    } catch (error) {
                        console.log('Re-authentication triggered:', error);
                        // Redirect to /saturn/ to prompt login
                        window.location.href = '/saturn/';
                    }
                }
            } catch (error) {
                console.error('Exit error:', error);
                document.getElementById('output').innerHTML += `<span style="color:#FF0000">Error during exit: ${error.message}</span>\n`;
            }
        });

        // Toggle versions display
        document.getElementById('show-versions').addEventListener('change', function() {
            document.getElementById('versions-container').style.display = this.checked ? 'block' : 'none';
        });

        console.log('Loading initial scripts, versions, and themes');
        loadScripts();
        loadVersions();
        loadThemes();
    </script>
</body>
</html>
EOF
chmod 644 "$INDEX_HTML"
chown pi:pi "$INDEX_HTML"
log_and_echo "${GREEN}index.html created${NC}"
if ! grep -q "Saturn Update Manager" "$INDEX_HTML" || ! grep -q "script-form" "$INDEX_HTML" || ! grep -q "version-list" "$INDEX_HTML" || ! grep -q "spinner" "$INDEX_HTML"; then
    log_and_echo "${RED}Error: Failed to create valid index.html${NC}"
    exit 1
fi
log_and_echo "${GREEN}Verified index.html content${NC}"

# Create saturn_update_manager.py (overwriting if exists)...
rm -f "$SATURN_SCRIPT"
cat > "$SATURN_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# saturn_update_manager.py - Web-based Update Manager for various scripts via config.json and themes via themes.json
# Version: 2.22
# Written by: Jerry DeLong KD4YAL
# Dependencies: flask, ansi2html (1.9.2), subprocess, os, threading, logging, re, shutil, select, urllib.error, json
# Usage: . ~/venv/bin/activate; gunicorn -w 1 -b 0.0.0.0:5000 -t 600 saturn_update_manager:app

import logging
import os
import glob
from pathlib import Path
from datetime import datetime
import subprocess
import threading
import shlex
import re
import shutil
import signal
import sys
import time
import select
import urllib.error
import json
from flask import Flask, render_template, request, Response, jsonify
from ansi2html import Ansi2HTMLConverter

# Initialize logging
log_dir = Path.home() / "saturn-logs"
log_dir.mkdir(parents=True, exist_ok=True)
os.chmod(log_dir, 0o775)
log_file = log_dir / f"saturn-update-manager-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(log_file)]
)
logging.info("Initializing Saturn Update Manager")

app = Flask(__name__, template_folder=os.path.join(Path.home(), 'scripts', 'templates'))
shutdown_event = threading.Event()

class SaturnUpdateManager:
    def __init__(self):
        logging.debug("Starting SaturnUpdateManager initialization")
        self.venv_path = Path.home() / "venv" / "bin" / "activate"
        self.scripts_dir = Path.home() / "scripts"
        self.log_dir = Path.home() / "saturn-logs"
        self.config_path = Path.home() / "scripts" / "config.json"
        self.themes_path = Path.home() / "scripts" / "themes.json"
        self.config = []
        self.themes = []
        self.versions = {
            "saturn_update_manager.py": "2.22"
        }
        self.process = None
        self.backup_response = None
        self.running = False
        self.output_lock = threading.Lock()
        self.converter = Ansi2HTMLConverter(inline=True)
        logging.info(f"Starting Saturn Update Manager v2.22")

        error_message = self.validate_setup()
        if error_message:
            logging.error(f"Initialization failed: {error_message}")
            print(f"Error: {error_message}\nCheck log: {log_file}")
            sys.exit(1)

        self.load_config()
        self.load_themes()

    def load_config(self):
        logging.debug(f"Loading config from {self.config_path}")
        self.script_warnings = []
        self.grouped_scripts = {}
        if not self.config_path.exists():
            logging.error(f"Config file not found: {self.config_path}")
            self.script_warnings.append("Config file missing—using empty config")
            return
        try:
            with open(self.config_path, 'r') as f:
                data = json.load(f)
            if not isinstance(data, list):
                raise ValueError("config.json must be a list of script entries")
            home = os.path.expanduser("~")
            trusted_dirs = [os.path.join(home, "github"), home]  # Expandable
            for entry in data:
                directory = os.path.expanduser(entry.get("directory", ""))
                filename = entry.get("filename", "")
                path = os.path.join(directory, filename)
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    if any(path.startswith(d) for d in trusted_dirs):
                        entry["category"] = entry.get("category", "Uncategorized")
                        self.config.append(entry)
                        # Extract version if present
                        with open(path, 'r') as script_file:
                            for line in script_file:
                                if line.startswith("# Version:"):
                                    self.versions[filename] = line.split(":", 1)[-1].strip()
                                    break
                    else:
                        self.script_warnings.append(f"Skipped {filename}: outside trusted directories")
                else:
                    self.script_warnings.append(f"Skipped {filename}: missing or not executable")
            for script in self.config:
                cat = script["category"]
                if cat not in self.grouped_scripts:
                    self.grouped_scripts[cat] = []
                self.grouped_scripts[cat].append(script)
            logging.info(f"Loaded {len(self.config)} valid scripts from config")
        except (json.JSONDecodeError, ValueError) as e:
            logging.error(f"Config error: {str(e)}")
            self.script_warnings.append(f"Invalid config.json: {str(e)} - using empty config")
        except Exception as e:
            logging.error(f"Error loading config: {str(e)}")
            self.script_warnings.append(f"Config load error: {str(e)} - using empty config")

    def load_themes(self):
        logging.debug(f"Loading themes from {self.themes_path}")
        self.theme_warnings = []
        if not self.themes_path.exists():
            logging.error(f"Themes file not found: {self.themes_path}")
            self.theme_warnings.append("Themes file missing—using empty themes")
            return
        try:
            with open(self.themes_path, 'r') as f:
                data = json.load(f)
            if not isinstance(data, list):
                raise ValueError("themes.json must be a list of theme entries")
            for entry in data:
                if "name" in entry and "styles" in entry and isinstance(entry["styles"], dict):
                    self.themes.append(entry)
                else:
                    self.theme_warnings.append(f"Skipped invalid theme: {entry.get('name', 'unnamed')}")
            logging.info(f"Loaded {len(self.themes)} valid themes from themes.json")
        except (json.JSONDecodeError, ValueError) as e:
            logging.error(f"Themes error: {str(e)}")
            self.theme_warnings.append(f"Invalid themes.json: {str(e)} - using empty themes")
        except Exception as e:
            logging.error(f"Error loading themes: {str(e)}")
            self.theme_warnings.append(f"Themes load error: {str(e)} - using empty themes")

    def validate_setup(self):
        try:
            logging.debug("Validating setup...")
            if not self.venv_path.exists():
                logging.error(f"Virtual environment not found at {self.venv_path}")
                return f"Virtual environment not found at {self.venv_path}"
            try:
                import flask
                import ansi2html
                import shutil
                import urllib.error
                logging.debug(f"ansi2html version: {ansi2html.__version__}")
                if ansi2html.__version__ != '1.9.2':
                    logging.error(f"Invalid ansi2html version: {ansi2html.__version__}. Requires 1.9.2")
                    return f"Invalid ansi2html version: {ansi2html.__version__}. Requires 1.9.2"
            except ImportError as e:
                logging.error(f"Missing dependency: {str(e)}. Install with: pip install flask ansi2html==1.9.2")
                return f"Missing dependency: {str(e)}. Install with: pip install flask ansi2html==1.9.2"
            python_version = subprocess.check_output(["python3", "--version"], stderr=subprocess.STDOUT).decode().strip()
            logging.info(f"Python version: {python_version}")
            if not python_version.startswith("Python 3"):
                logging.error(f"Incompatible Python version: {python_version}. Requires 3.x")
                return f"Incompatible Python version: {python_version}. Requires 3.x"
            logging.debug("Setup validation completed successfully")
            return None
        except Exception as e:
            logging.error(f"Setup validation failed: {str(e)}")
            return f"Setup validation failed: {str(e)}"

    def install_desktop_icons(self):
        logging.debug("Installing desktop icons...")
        desktop_dir = self.scripts_dir
        home_desktop = Path.home() / "Desktop"
        desktop_file = desktop_dir / "SaturnUpdateManager.desktop"
        dest_file = home_desktop / "SaturnUpdateManager.desktop"

        if not desktop_file.exists():
            logging.info(f"Creating desktop file: {desktop_file}")
            with desktop_file.open("w") as f:
                f.write(f"""[Desktop Entry]
Type=Application
Name=Saturn Update Manager
Comment=Web-based GUI to manage updates for various scripts
Exec=xdg-open http://localhost/saturn/
Icon=system-software-update
Terminal=false
Categories=System;Utility;
""")
            try:
                os.chmod(desktop_file, 0o755)
                logging.info(f"Created desktop file: {desktop_file}")
            except Exception as e:
                logging.error(f"Failed to set permissions for {desktop_file}: {str(e)}")
                return False
        try:
            if not home_desktop.exists():
                logging.warning(f"Home Desktop directory does not exist: {home_desktop}")
                return False
            shutil.copy2(desktop_file, dest_file)
            os.chmod(dest_file, 0o755)
            logging.info(f"Installed desktop shortcut: {dest_file}")
            return True
        except Exception as e:
            logging.error(f"Shortcut install failed: {str(e)}")
            return False

    def change_password(self, new_password):
        logging.debug(f"Attempting to change password for user: admin")
        if len(new_password) < 8:
            logging.error("Password too short")
            return {"status": "error", "message": "Password must be at least 8 characters"}
        try:
            result = subprocess.run(
                ['sudo', '/usr/bin/htpasswd', '-b', '/etc/apache2/.htpasswd', 'admin', new_password],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                logging.info("Password changed successfully for user: admin")
                return {"status": "success", "message": "Password changed successfully"}
            else:
                logging.error(f"Failed to change password: {result.stderr}")
                return {"status": "error", "message": f"Failed to change password: {result.stderr}"}
        except Exception as e:
            logging.error(f"Error changing password: {str(e)}")
            return {"status": "error", "message": f"Error changing password: {str(e)}"}

    def get_backups(self, type):
        if type not in ['pihpsdr', 'saturn']:
            return {"error": "Invalid type"}
        pattern = f"~/{type}-backup-*"
        backups = sorted(glob.glob(os.path.expanduser(pattern)), key=os.path.getmtime, reverse=True)
        backups = [os.path.basename(b) for b in backups]
        return {"backups": backups}

    def run_script(self, filename, flags):
        logging.debug(f"Running script: {filename} with flags: {flags}")
        self.running = True
        self.process = None
        self.backup_response = None
        script_entry = next((s for s in self.config if s["filename"] == filename), None)
        if not script_entry:
            logging.error(f"Script not found in config: {filename}")
            error_msg = f"Error: Script {filename} not found\n"
            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
            return
        script_path = os.path.join(os.path.expanduser(script_entry["directory"]), filename)
        if not os.path.isfile(script_path):
            logging.error(f"Script path invalid: {script_path}")
            error_msg = f"Error: Script path invalid {script_path}\n"
            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
            return
        if filename.endswith('.sh'):
            cmd = f"bash {shlex.quote(script_path)} {' '.join(shlex.quote(flag) for flag in flags)}"
            test_cmd = f"bash -n {shlex.quote(script_path)}"
        else:
            cmd = f". {self.venv_path} && python3 {shlex.quote(script_path)} {' '.join(shlex.quote(flag) for flag in flags)} && deactivate"
            test_cmd = f". {self.venv_path} && python3 -m py_compile {shlex.quote(script_path)}"
        logging.info(f"Executing command: {cmd}")

        try:
            # Test script syntax
            logging.debug(f"Testing script syntax with: {test_cmd}")
            test_result = subprocess.run(test_cmd, shell=True, capture_output=True, text=True, timeout=10)
            if test_result.returncode != 0:
                logging.error(f"Syntax check failed: {test_result.stderr}")
                error_msg = f"Error: Syntax check failed: {test_result.stderr}\n"
                yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                return
            logging.debug(f"Syntax check passed")

            env = os.environ.copy()
            env["PYTHONUNBUFFERED"] = "1"
            env["PATH"] = f"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:{env.get('PATH', '')}"
            env["HOME"] = str(Path.home())
            if not filename.endswith('.sh'):
                env["PYTHONPATH"] = f"{str(self.venv_path.parent / 'lib' / 'python3.11' / 'site-packages')}:{env.get('PYTHONPATH', '')}"
            env["LC_ALL"] = "en_US.UTF-8"
            env["TERM"] = env.get("TERM", "dumb")
            logging.debug(f"Environment: {env}")

            self.process = subprocess.Popen(
                cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                stdin=subprocess.PIPE, text=True, bufsize=1, universal_newlines=True, env=env
            )
            logging.debug(f"Started process with PID: {self.process.pid}")
            backup_prompt = re.compile(r'⚠?\s*Backup\?\s*Y/n\s*:?', re.IGNORECASE)
            timeout = 600
            start_time = datetime.now()
            output_buffer = []
            last_heartbeat = time.time()
            while self.process.poll() is None:
                try:
                    if time.time() - last_heartbeat > 5:
                        with self.output_lock:
                            yield "data: \n\n"
                            logging.debug("Sent heartbeat")
                            sys.stdout.flush()
                        last_heartbeat = time.time()

                    rlist, _, _ = select.select([self.process.stdout, self.process.stderr], [], [], 0.1)
                    for stream in rlist:
                        if stream is self.process.stdout:
                            line = stream.readline()
                        elif stream is self.process.stderr:
                            line = stream.readline()
                        else:
                            continue

                        if not line:
                            continue

                        with self.output_lock:
                            clean_line = re.sub(r'\x1B\[[0-?]*[ -/]*[@-~]', '', line)
                            converted_line = self.converter.convert(line.rstrip('\n'), full=False)
                            output_buffer.append(converted_line)

                            if stream is self.process.stdout:
                                logging.debug(f"stdout: {clean_line.strip()}")
                                if backup_prompt.search(clean_line) and '-y' not in flags and '-n' not in flags:
                                    logging.info("Detected backup prompt")
                                    yield "data: BACKUP_PROMPT\n\n"
                                    sys.stdout.flush()
                                    while self.backup_response is None and self.process.poll() is None:
                                        if (datetime.now() - start_time).seconds > timeout:
                                            logging.error("Backup prompt timed out")
                                            error_msg = "Error: Backup prompt timed out after 600 seconds\n"
                                            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                                            sys.stdout.flush()
                                            self.process.terminate()
                                            break
                                        time.sleep(0.2)
                                    if self.backup_response:
                                        try:
                                            self.process.stdin.write(self.backup_response + '\n')
                                            self.process.stdin.flush()
                                            logging.info(f"Sent backup response: {self.backup_response}")
                                        except Exception as e:
                                            logging.error(f"Failed to send backup response: {str(e)}")
                                            error_msg = f"Error sending backup response: {e}\n"
                                            yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                                            sys.stdout.flush()
                            else:
                                logging.error(f"stderr: {clean_line.strip()}")
                                if "tput: No value for $TERM" in clean_line:
                                    logging.warning(f"Ignoring tput error: {clean_line.strip()}")
                                elif "network error" in clean_line.lower():
                                    logging.error(f"Network error detected in stderr: {clean_line.strip()}")
                                    error_msg = f"Error: Network issue during script execution: {clean_line.strip()}. Check connectivity and try again.\n"
                                    yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                                    sys.stdout.flush()

                            if len(output_buffer) >= 10:
                                chunk = "\n".join(output_buffer)
                                logging.debug(f"Streaming chunk: {chunk}")
                                yield f"data: {chunk}\n\n"
                                sys.stdout.flush()
                                output_buffer = []

                    time.sleep(0.005)
                except (BrokenPipeError, ConnectionResetError) as e:
                    logging.error(f"Stream interrupted: {str(e)}")
                    error_msg = f"Error: Stream interrupted: {str(e)}\n"
                    yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                    sys.stdout.flush()
                    break
                except urllib.error.URLError as e:
                    logging.error(f"Network error during script execution: {str(e)}")
                    error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
                    yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                    sys.stdout.flush()
                    break

            with self.output_lock:
                if output_buffer:
                    chunk = "\n".join(output_buffer)
                    logging.debug(f"Streaming final chunk: {chunk}")
                    yield f"data: {chunk}\n\n"
                    sys.stdout.flush()

            stdout, stderr = self.process.communicate()
            if stdout:
                with self.output_lock:
                    logging.debug(f"Final script stdout: {stdout.strip()}")
                    converted_output = self.converter.convert(stdout.rstrip('\n'), full=False)
                    yield f"data: {converted_output}\n\n"
                    sys.stdout.flush()
            if stderr:
                with self.output_lock:
                    logging.error(f"Final script stderr: {stderr.strip()}")
                    converted_err = self.converter.convert(stderr.rstrip('\n'), full=False)
                    yield f"data: {converted_err}\n\n"
                    sys.stdout.flush()
                    if "tput: No value for $TERM" in stderr:
                        logging.warning(f"Ignoring tput error in final stderr: {stderr.strip()}")
                    elif "network error" in stderr.lower():
                        logging.error(f"Network error in final stderr: {stderr.strip()}")
                        error_msg = f"Error: Network issue in final output: {stderr.strip()}. Check connectivity and retry.\n"
                        yield f"data: {self.converter.convert(error_msg, full=False)}\n\n"
                        sys.stdout.flush()
            if self.process.returncode == 0:
                success_msg = f"Completed: Log at ~/saturn-logs/{filename.replace('.py', '').replace('.sh', '')}-*.log\n"
                with self.output_lock:
                    converted_success = self.converter.convert(success_msg, full=False)
                    logging.debug(f"Success message HTML: {converted_success}")
                    yield f"data: {converted_success}\n\n"
                    sys.stdout.flush()
                    logging.info(f"Script {filename} completed successfully with PID {self.process.pid}")
            else:
                error_msg = f"Failed: Check output for errors (return code: {self.process.returncode})\n"
                with self.output_lock:
                    converted_error = self.converter.convert(error_msg, full=False)
                    logging.debug(f"Error message HTML: {converted_error}")
                    yield f"data: {converted_error}\n\n"
                    sys.stdout.flush()
                    logging.error(f"Script {filename} failed with return code {self.process.returncode}")
        except Exception as e:
            logging.error(f"Script execution failed: {str(e)}")
            error_msg = f"Error: {str(e)}\n"
            if isinstance(e, urllib.error.URLError):
                error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
            with self.output_lock:
                converted_error = self.converter.convert(error_msg, full=False)
                yield f"data: {converted_error}\n\n"
                sys.stdout.flush()
        finally:
            self.running = False
            self.process = None
            logging.debug("Script execution completed")

    def get_versions(self):
        logging.debug("Fetching script versions")
        versions = self.versions
        logging.info(f"Returning versions: {versions}")
        return versions

@app.route('/ping')
def ping():
    logging.debug(f"Ping request received, client: {request.remote_addr}, headers: {request.headers}")
    response = Response("pong")
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response

@app.route('/saturn/')
def index():
    logging.debug(f"Serving index page for /saturn/, client: {request.remote_addr}, headers: {request.headers}")
    try:
        return render_template('index.html')
    except Exception as e:
        logging.error(f"Error rendering index.html: {str(e)}")
        return f"Error rendering index.html: {str(e)}", 500

@app.route('/saturn/get_scripts', methods=['GET'])
def get_scripts():
    logging.debug(f"Fetching available scripts for /saturn/get_scripts, client: {request.remote_addr}, headers: {request.headers}")
    response = jsonify({"scripts": app.saturn.grouped_scripts, "warnings": app.saturn.script_warnings})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/saturn/get_themes', methods=['GET'])
def get_themes():
    logging.debug(f"Fetching available themes for /saturn/get_themes, client: {request.remote_addr}, headers: {request.headers}")
    themes = [{"name": t["name"], "description": t.get("description", "")} for t in app.saturn.themes]
    response = jsonify({"themes": themes, "warnings": app.saturn.theme_warnings})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/saturn/get_theme', methods=['GET'])
def get_theme():
    name = request.args.get('name')
    logging.debug(f"Fetching theme {name} for /saturn/get_theme, client: {request.remote_addr}, headers: {request.headers}")
    theme = next((t for t in app.saturn.themes if t["name"] == name), None)
    if theme:
        response = jsonify({"styles": theme["styles"]})
    else:
        response = jsonify({"error": f"Theme not found: {name}"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200 if theme else 404

@app.route('/saturn/get_versions', methods=['GET'])
def get_versions():
    logging.debug(f"Fetching script versions for /saturn/get_versions, client: {request.remote_addr}, headers: {request.headers}")
    versions = app.saturn.get_versions()
    response = jsonify({"versions": versions})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200

@app.route('/saturn/get_flags', methods=['GET'])
def get_flags():
    filename = request.args.get('script')
    logging.debug(f"Fetching flags for script: {filename} on /saturn/get_flags, client: {request.remote_addr}, headers: {request.headers}")
    for script in app.saturn.config:
        if script["filename"] == filename:
            logging.info(f"Returning flags for {filename}: {script['flags']}")
            response = jsonify({"flags": script["flags"]})
            response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
            response.headers['Pragma'] = 'no-cache'
            response.headers['Expires'] = '0'
            return response, 200
    logging.warning(f"Invalid script requested: {filename}")
    response = jsonify({"flags": [], "error": f"Invalid script: {filename}"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 404

@app.route('/saturn/get_backups', methods=['GET'])
def get_backups():
    try:
        type = request.args.get('type')
        logging.debug(f"Fetching backups for type: {type}")
        backups = app.saturn.get_backups(type)
        status = 200
        if "error" in backups:
            status = 400
        return jsonify(backups), status
    except Exception as e:
        logging.error(f"Error in get_backups endpoint: {str(e)}")
        return jsonify({"error": "Internal server error: " + str(e)}), 500

@app.route('/saturn/run', methods=['POST'])
def run():
    filename = request.form.get('script')
    flags = request.form.getlist('flags')
    backup_dir = request.form.get('backup_dir', '')
    logging.debug(f"Received run request for script: {filename}, flags: {flags}, backup_dir: {backup_dir}")
    if backup_dir:
        flags.append('--backup-dir')
        flags.append(backup_dir)
    if not filename:
        logging.error(f"Invalid script: {filename}")
        error_msg = f"Error: Invalid script {filename}\n"
        response = Response(f"data: {app.saturn.converter.convert(error_msg, full=False)}\n\n", mimetype='text/event-stream', status=400)
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        response.headers['Content-Type'] = 'text/event-stream; charset=utf-8'
        response.headers['X-Accel-Buffering'] = 'no'
        return response

    def generate():
        try:
            for output in app.saturn.run_script(filename, flags):
                logging.debug(f"Streaming event: {output}")
                yield output
                sys.stdout.flush()
        except Exception as e:
            logging.error(f"Run endpoint error: {str(e)}")
            error_msg = f"Error: {str(e)}\n"
            if isinstance(e, urllib.error.URLError):
                error_msg = f"Error: Network failure: {str(e)}. Please check your internet connection and try again.\n"
            converted_error = app.saturn.converter.convert(error_msg, full=False)
            yield f"data: {converted_error}\n\n"
            sys.stdout.flush()

    response = Response(generate(), mimetype='text/event-stream')
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    response.headers['Content-Type'] = 'text/event-stream; charset=utf-8'
    response.headers['X-Accel-Buffering'] = 'no'
    return response

@app.route('/saturn/backup_response', methods=['POST'])
def backup_response():
    response = request.form.get('response')
    logging.debug(f"Received backup response: {response} on /saturn/backup_response, client: {request.remote_addr}, headers: {request.headers}")
    if response in ['y', 'n']:
        app.saturn.backup_response = response
        logging.info(f"Backup response set: {response}")
        response = jsonify({"status": "success"})
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response, 200
    logging.error(f"Invalid backup response: {response}")
    response = jsonify({"status": "error", "message": "Invalid response"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 400

@app.route('/saturn/change_password', methods=['POST'])
def change_password():
    new_password = request.form.get('new_password')
    logging.debug(f"Received change password request, client: {request.remote_addr}, headers: {request.headers}")
    result = app.saturn.change_password(new_password)
    response = jsonify(result)
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response, 200 if result['status'] == 'success' else 400

@app.route('/saturn/exit', methods=['POST'])
def exit_app():
    logging.debug(f"Received exit request on /saturn/exit, client: {request.remote_addr}, headers: {request.headers}")
    if app.saturn.process:
        try:
            app.saturn.process.terminate()
            app.saturn.process.wait(timeout=5)
            logging.info("Terminated running script")
        except subprocess.TimeoutExpired:
            app.saturn.process.kill()
            logging.warning("Forced termination of running script")
    logging.info("Initiating server shutdown and logoff")
    response = jsonify({"status": "shutting down"})
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    response.headers['WWW-Authenticate'] = 'Basic realm="Saturn Update Manager - Restricted Access"'
    # Start shutdown in a separate thread
    def shutdown():
        try:
            time.sleep(1)  # Brief delay to allow response to be sent
            os.kill(os.getpid(), signal.SIGINT)
        except Exception as e:
            logging.error(f"Shutdown error: {str(e)}")
            sys.exit(1)
    threading.Thread(target=shutdown, daemon=True).start()
    return response, 401

try:
    logging.debug("Creating SaturnUpdateManager instance")
    app.saturn = SaturnUpdateManager()
    app.saturn.install_desktop_icons()
except Exception as e:
    error_log = Path.home() / "saturn-logs" / f"saturn-update-manager-error-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
    with open(error_log, "w") as f:
        f.write(f"Web server initialization error: {str(e)}\n")
    logging.error(f"Web server initialization error: {str(e)}")
    sys.exit(1)
EOF
chmod +x "$SATURN_SCRIPT"
chown pi:pi "$SATURN_SCRIPT"
log_and_echo "${GREEN}saturn_update_manager.py created${NC}"
log_and_echo "${CYAN}Validating saturn_update_manager.py syntax...${NC}"
sudo rm -rf "$SCRIPTS_DIR/__pycache__"
sudo chown -R pi:pi "$SCRIPTS_DIR"
sudo chmod -R 775 "$SCRIPTS_DIR"
if output=$(sudo -u pi bash -c ". $VENV_PATH/bin/activate && python3 -m py_compile $SATURN_SCRIPT" 2>&1); then
    log_and_echo "${GREEN}Syntax validation passed${NC}"
else
    log_and_echo "${RED}Error: Syntax validation failed${NC}"
    log_and_echo "$output"
    exit 1
fi
log_and_echo "${GREEN}Verified Flask-based saturn_update_manager.py${NC}"

# Create log_cleaner.sh (overwriting if exists)...
log_and_echo "${CYAN}Creating log_cleaner.sh in $SCRIPTS_DIR (overwriting if exists)...${NC}"
rm -f "$LOG_CLEANER_SCRIPT"
cat > "$LOG_CLEANER_SCRIPT" << 'EOF'
#!/bin/bash
# log_cleaner.sh - Script to find *.log files in home directory, report total space used, and optionally delete them
# Usage: ./log_cleaner.sh [--delete-all] [--recursive] [--dry-run]

# Flags
DELETE_ALL=false
RECURSIVE=true  # Default to recursive search
DRY_RUN=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --delete-all) DELETE_ALL=true ;;
        --no-recursive) RECURSIVE=false ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

HOME_DIR="$HOME"

# Build find command
FIND_CMD="find $HOME_DIR -maxdepth 1 -type f -name '*.log'"  # Non-recursive by default
if $RECURSIVE; then
    FIND_CMD="find $HOME_DIR -type f -name '*.log'"
fi

# Find all *.log files
LOG_FILES=$($FIND_CMD)

if [ -z "$LOG_FILES" ]; then
    echo "No *.log files found in $HOME_DIR."
    exit 0
fi

# Calculate total size
TOTAL_SIZE=$($FIND_CMD -exec du -b {} + | awk '{total += $1} END {print total}')

# Human-readable size
if command -v numfmt &> /dev/null; then
    HUMAN_SIZE=$(numfmt --to=iec-i --suffix=B --padding=7 $TOTAL_SIZE)
else
    HUMAN_SIZE="$TOTAL_SIZE bytes"
fi

echo "Total space used by *.log files: $HUMAN_SIZE"

# List files with sizes
echo "Log files found:"
while IFS= read -r file; do
    SIZE=$(du -h "$file" | cut -f1)
    echo "- $file ($SIZE)"
done <<< "$LOG_FILES"

# Deletion logic
if $DELETE_ALL; then
    if $DRY_RUN; then
        echo "[Dry run] Would delete all found *.log files."
    else
        while IFS= read -r file; do
            rm -f "$file"
            echo "Deleted: $file"
        done <<< "$LOG_FILES"
        echo "All *.log files deleted."
    fi
else
    read -p "Delete all these files? (y/n): " confirm
    if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
        if $DRY_RUN; then
            echo "[Dry run] Would delete all found *.log files."
        else
            while IFS= read -r file; do
                rm -f "$file"
                echo "Deleted: $file"
            done <<< "$LOG_FILES"
            echo "All *.log files deleted."
        fi
    else
        echo "Deletion cancelled."
    fi
fi
EOF
chmod +x "$LOG_CLEANER_SCRIPT"
chown pi:pi "$LOG_CLEANER_SCRIPT"
log_and_echo "${GREEN}log_cleaner.sh created${NC}"

# Create restore-backup.sh (overwriting if exists)...
log_and_echo "${CYAN}Creating restore-backup.sh in $SCRIPTS_DIR (overwriting if exists)...${NC}"
rm -f "$RESTORE_SCRIPT"
cat > "$RESTORE_SCRIPT" << 'EOF'
#!/bin/bash
# restore-backup.sh - Restore from Saturn or piHPSDR backup directories
# Version: 1.0
# Usage: ./restore-backup.sh [--pihpsdr|--saturn] [--latest|--list|--backup-dir <dir>] [--dry-run] [--verbose]
# Assumes backups are directories in ~/ named saturn-backup-YYYYMMDD-HHMMSS or pihpsdr-backup-YYYYMMDD-HHMMSS.

set -e

HOME_DIR="$HOME"
SATURN_DIR="$HOME/github/Saturn"
PIHPSDR_DIR="$HOME/github/pihpsdr"

TYPE=""
LATEST=false
LIST=false
BACKUP_DIR_ARG=""
DRY_RUN=false
VERBOSE=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --pihpsdr) TYPE="pihpsdr" ;;
        --saturn) TYPE="saturn" ;;
        --latest) LATEST=true ;;
        --list) LIST=true ;;
        --backup-dir) BACKUP_DIR_ARG="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --verbose) VERBOSE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$TYPE" ]; then
    echo "Error: Must specify --pihpsdr or --saturn"
    exit 1
fi

BACKUP_PATTERN="$HOME_DIR/${TYPE}-backup-*"
TARGET_DIR=$( [ "$TYPE" = "pihpsdr" ] && echo "$PIHPSDR_DIR" || echo "$SATURN_DIR" )
RSYNC_OPTS="-a"
if $VERBOSE; then RSYNC_OPTS="-av"; fi
if $DRY_RUN; then RSYNC_OPTS="$RSYNC_OPTS --dry-run"; fi

if $LIST; then
    echo "Available $TYPE backups:"
    backups=$(ls -dt $BACKUP_PATTERN 2>/dev/null)
    if [ -z "$backups" ]; then
        echo "No backups found."
    else
        echo "$backups" | xargs -n1 basename
    fi
    exit 0
fi

SELECTED_BACKUP=""
if [ -n "$BACKUP_DIR_ARG" ]; then
    if [ -d "$BACKUP_DIR_ARG" ]; then
        SELECTED_BACKUP="$BACKUP_DIR_ARG"
    else
        SELECTED_BACKUP="$HOME_DIR/$BACKUP_DIR_ARG"
        if ! [ -d "$SELECTED_BACKUP" ]; then
            echo "Invalid backup directory: $BACKUP_DIR_ARG"
            exit 1
        fi
    fi
elif $LATEST; then
    SELECTED_BACKUP=$(ls -dt $BACKUP_PATTERN 2>/dev/null | head -1)
    if [ -z "$SELECTED_BACKUP" ]; then
        echo "No $TYPE backup found in $HOME_DIR."
        exit 1
    fi
else
    echo "Usage: Specify --latest or --backup-dir <dir> to restore, --list to list backups."
    exit 1
fi

if $VERBOSE; then
    echo "Restoring from $SELECTED_BACKUP to $TARGET_DIR"
fi
rsync $RSYNC_OPTS "$SELECTED_BACKUP/" "$TARGET_DIR/"
if ! $DRY_RUN; then
    echo "Restore completed. Reboot recommended."
fi
EOF
chmod +x "$RESTORE_SCRIPT"
chown pi:pi "$RESTORE_SCRIPT"
log_and_echo "${GREEN}restore-backup.sh created${NC}"

# Create SaturnUpdateManager.desktop (overwriting if exists)...
rm -f "$DESKTOP_FILE"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Saturn Update Manager
Comment=Web-based GUI to manage updates for various scripts
Exec=xdg-open http://localhost:5000/saturn/
Icon=system-software-update
Terminal=false
Categories=System;Utility;
EOF
chmod +x "$DESKTOP_FILE"
chown pi:pi "$DESKTOP_FILE"
log_and_echo "${GREEN}SaturnUpdateManager.desktop created${NC}"

# Install desktop shortcut
log_and_echo "${CYAN}Installing desktop shortcut...${NC}"
cp "$DESKTOP_FILE" "$DESKTOP_DEST"
chmod +x "$DESKTOP_DEST"
chown pi:pi "$DESKTOP_DEST"
log_and_echo "${GREEN}Desktop shortcut installed to $DESKTOP_DEST${NC}"

# Verify scripts
log_and_echo "${CYAN}Checking for update-G2.py and update-pihpsdr.py...${NC}"
for script in "update-G2.py" "update-pihpsdr.py"; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        log_and_echo "${RED}Error: $script not found at $SCRIPTS_DIR/$script. Please ensure it exists.${NC}"
        exit 1
    else
        chmod +x "$SCRIPTS_DIR/$script"
        chown pi:pi "$SCRIPTS_DIR/$script"
        version=$(grep "Version:" "$SCRIPTS_DIR/$script" | head -n1 | awk '{print $NF}')
        log_and_echo "${GREEN}$script verified (version $version) and permissions set${NC}"
    fi
done
