# VNC Setup Manager - Complete Guide & Documentation

## Table of Contents
1. [Overview](#overview)
2. [What This Script Does](#what-this-script-does)
3. [Understanding VNC Displays](#understanding-vnc-displays)
4. [Key Concepts Explained](#key-concepts-explained)
5. [Code Explanations](#code-explanations)
6. [Installation & Usage](#installation--usage)
7. [Troubleshooting](#troubleshooting)

---

## Overview

This script automates the setup and management of a VNC (Virtual Network Computing) server on openSUSE Tumbleweed. It allows you to remotely access your Linux desktop from another computer using tools like Remmina.

### What is VNC?

VNC (Virtual Network Computing) is a graphical desktop-sharing system that uses the Remote Frame Buffer (RFB) protocol to remotely control another computer. It transmits keyboard and mouse events from one computer to another, relaying the graphical screen updates back in the other direction.

### Why This Script?

Setting up VNC manually is complex and error-prone, especially on modern Linux systems with:
- Dynamic XAUTHORITY paths
- Systemd service management
- Firewall configuration
- Graphics hardware variations

This script handles all of that automatically.

---

## What This Script Does

### Automated Tasks

1. **Dependency Management**
   - Checks if TigerVNC is installed
   - Offers to install it automatically
   - Verifies all required components

2. **Graphics Detection**
   - Detects your GPU (Intel, NVIDIA, AMD)
   - Applies optimized settings for older hardware (like Intel 965Q)

3. **File Creation**
   - Creates `~/.vnc/` directory with correct permissions (700)
   - Generates password file with correct permissions (600)
   - Creates configuration files
   - Generates startup script (`~/start-vnc.sh`)
   - Creates systemd service file

4. **System Configuration**
   - Configures firewall to allow VNC connections
   - Sets up systemd service for auto-start on boot
   - Enables user lingering (service runs even when not logged in)

5. **Service Management**
   - Start/Stop/Restart VNC server
   - Enable/Disable auto-start on boot
   - View status and logs
   - Complete uninstallation

---

## Understanding VNC Displays

### Two Approaches to VNC

#### 1. **Virtual Desktop (vncserver)**
Creates a NEW virtual desktop session separate from your physical display.

```
Your Computer:
├── Physical Display :0 (your monitor - KDE Plasma running here)
└── Virtual Display :1 (VNC creates this - new desktop session)
```

**Pros:**
- Can run different desktop environment
- Multiple users can have separate sessions
- Continues running even if you log out physically

**Cons:**
- Black screen issues with complex desktop environments
- Need to start desktop environment separately
- More resource intensive

#### 2. **Desktop Sharing (x0vncserver)** ⭐ This script uses this
Shares your EXISTING desktop that's already running on :0.

```
Your Computer:
└── Physical Display :0 (your monitor)
    └── x0vncserver shares THIS display via VNC
```

**Pros:**
- See exactly what's on your physical monitor
- No black screen issues
- Less resource intensive
- Easier to set up

**Cons:**
- Only works with X11 (not Wayland)
- Shows your actual desktop (not private)
- If you log out, VNC disconnects

### Display Numbers Explained

In X11 (the window system), displays are numbered:

- `:0` = First display (usually your physical monitor)
- `:1` = Second display (virtual or second monitor)
- `:2` = Third display, etc.

VNC ports correspond to displays:
- Display `:0` → Port `5900`
- Display `:1` → Port `5901`
- Display `:2` → Port `5902`

**This script uses display `:0` (port 5900) to share your existing desktop.**

---

## Key Concepts Explained

### XAUTHORITY

**What it is:**
A file that contains authentication credentials for X11 display access.

**Why it matters:**
Without the correct XAUTHORITY file, programs (including x0vncserver) cannot access your X display, resulting in the dreaded black screen or "Unable to open display" errors.

**The Problem:**
On modern Linux systems, XAUTHORITY is often created in `/tmp/` with a random name like `/tmp/xauth_POSyok` that changes on each login.

**How this script handles it:**
```bash
if [ -z "$XAUTHORITY" ]; then
    if [ -f "$HOME/.Xauthority" ]; then
        export XAUTHORITY="$HOME/.Xauthority"
    else
        TEMP_AUTH=$(find /tmp -maxdepth 1 -name "xauth_*" -user $(whoami) 2>/dev/null | head -1)
        if [ -n "$TEMP_AUTH" ]; then
            export XAUTHORITY="$TEMP_AUTH"
        fi
    fi
fi
```

This searches for the XAUTHORITY file in common locations and sets it automatically.

### Systemd Service

**What it is:**
Systemd is the init system used by modern Linux distributions to manage services (programs that run in the background).

**User Services vs System Services:**
- **System services**: Run as root, start at boot
- **User services**: Run as your user, stored in `~/.config/systemd/user/`

This script creates a **user service** so VNC runs as your user account.

**Service File Location:**
```
~/.config/systemd/user/x0vncserver.service
```

**Key systemd commands:**
```bash
systemctl --user start x0vncserver    # Start now
systemctl --user stop x0vncserver     # Stop now
systemctl --user enable x0vncserver   # Auto-start on boot
systemctl --user disable x0vncserver  # Don't auto-start
systemctl --user status x0vncserver   # Check status
```

### User Lingering

**What it is:**
By default, user services only run when you're logged in. "Lingering" allows your user services to run even when you're not logged in.

**Command:**
```bash
loginctl enable-linger $USER
```

**Why it matters:**
Without lingering, your VNC server would stop when you log out physically, defeating the purpose of remote access.

### Firewall (firewalld)

**What it is:**
A security system that controls incoming and outgoing network traffic based on predetermined security rules.

**Why it matters:**
Even if VNC is running, the firewall might block external connections on port 5900.

**This script opens port 5900:**
```bash
sudo firewall-cmd --permanent --add-port=5900/tcp
sudo firewall-cmd --reload
```

- `--permanent`: Save the rule across reboots
- `--add-port=5900/tcp`: Allow TCP traffic on port 5900
- `--reload`: Apply changes immediately

---

## Code Explanations

### Bash Script Features

#### Shebang
```bash
#!/bin/bash
```
Tells the system to use bash to execute this script.

#### Set Options
```bash
set -e
```
- `-e`: Exit immediately if any command fails
- Prevents script from continuing after errors

#### Color Variables
```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color
```

These are ANSI escape codes for terminal colors:
- `\033[` = Escape sequence start
- `0;31m` = Color code (0=normal, 31=red)
- `NC` = Reset to default color

### Function: print_msg()

```bash
print_msg() {
    local color="$1"
    local msg="$2"
    
    if [ -t 2 ]; then
        echo -e "${color}${msg}${NC}" >&2
    else
        echo "$msg" >&2
    fi
}
```

**Explanation:**

**Parameters:**
- `$1` = First positional parameter (color)
- `$2` = Second positional parameter (message)

**What it does:**
1. `local color="$1"` - Creates local variable from first argument
2. `local msg="$2"` - Creates local variable from second argument
3. `[ -t 2 ]` - Tests if file descriptor 2 (stderr) is a terminal
4. `echo -e` - Print with escape sequence interpretation
5. `>&2` - Redirect output to stderr (not stdout)

**Why stderr instead of stdout?**
- Stdout is for data/results that can be captured
- Stderr is for messages/diagnostics
- This prevents diagnostic messages from polluting captured output

**Example usage:**
```bash
print_msg "$RED" "Error: Something went wrong"
print_msg "$GREEN" "Success: All done!"
```

### Function: detect_graphics()

```bash
detect_graphics() {
    print_msg "$BLUE" "Detecting graphics hardware..."

    local gpu_info
    gpu_info=$(lspci | grep -i vga)

    local gpu_type=""
    local vnc_options=""

    if echo "$gpu_info" | grep -qi "intel.*9[0-9][0-9]"; then
        gpu_type="Intel Legacy (Gen 4-7)"
        vnc_options="-AlwaysShared"
        print_msg "$YELLOW" "Detected: $gpu_type"
    elif echo "$gpu_info" | grep -qi "intel"; then
        gpu_type="Intel"
        vnc_options="-AlwaysShared"
        print_msg "$GREEN" "Detected: Intel graphics"
    # ... more conditions ...
    fi

    echo "$vnc_options"
}
```

**Command breakdown:**

**lspci:**
- Lists all PCI devices (graphics cards, network cards, etc.)
- PCI = Peripheral Component Interconnect (internal bus)

**grep -i vga:**
- `grep` = Search for patterns
- `-i` = Case-insensitive
- `vga` = Search for "VGA" (Video Graphics Array - graphics cards)

**Pattern matching:**
```bash
grep -qi "intel.*9[0-9][0-9]"
```
- `-q` = Quiet mode (no output, just exit code)
- `-i` = Case insensitive
- `"intel.*9[0-9][0-9]"` = Regular expression:
  - `intel` = Literal text "intel"
  - `.*` = Any characters (zero or more)
  - `9[0-9][0-9]` = 9 followed by any two digits (900-999)
  
Matches: "Intel 965", "Intel 945", etc.

**Return value:**
```bash
echo "$vnc_options"
```
Only this goes to stdout, so when called as:
```bash
local vnc_opts=$(detect_graphics)
```
The variable `vnc_opts` gets `-AlwaysShared`, not the diagnostic messages (which went to stderr).

### Regular Expression Matching

```bash
if [[ "$install_choice" =~ ^[Yy]$ ]]; then
```

**Explanation:**

**Double brackets `[[ ]]`:**
- Bash's enhanced test command
- Supports pattern matching and regular expressions

**`=~` operator:**
- Regular expression match operator
- Returns true if left side matches right side pattern

**Pattern `^[Yy]$`:**
- `^` = Start of string
- `[Yy]` = Character class - matches 'Y' or 'y'
- `$` = End of string

**Result:** Matches only "Y" or "y" (nothing else)

**Why not just `==`?**
```bash
if [ "$install_choice" == "y" ]; then  # Only matches lowercase 'y'
if [[ "$install_choice" =~ ^[Yy]$ ]]; # Matches 'y' OR 'Y'
```

### Redirect Operators

```bash
command &> /dev/null
```

**Breakdown:**
- `&>` = Redirect both stdout and stderr
- `/dev/null` = Special file that discards all data written to it (the "bit bucket")

**Effect:** Silences all output from the command

**Other redirect operators:**
```bash
>   # Redirect stdout only
2>  # Redirect stderr only
&>  # Redirect both stdout and stderr
>>  # Append stdout (instead of overwrite)
2>> # Append stderr
```

**Example:**
```bash
sudo firewall-cmd --permanent --add-port=5900/tcp &> /dev/null
```
Runs the firewall command but doesn't show any output.

### Command Substitution

```bash
local vnc_opts=$(detect_graphics)
```

**Syntax:** `$(command)`

**What it does:**
- Executes the command inside `$()`
- Captures stdout (not stderr)
- Assigns the output to the variable

**Older syntax:** Backticks `` `command` `` (deprecated)

**Example:**
```bash
current_user=$(whoami)       # Captures username
current_dir=$(pwd)            # Captures current directory
file_count=$(ls | wc -l)      # Counts files in directory
```

### Conditional Execution

```bash
command1 && command2  # Run command2 only if command1 succeeds
command1 || command2  # Run command2 only if command1 fails
```

**Example in script:**
```bash
loginctl enable-linger "$USER" 2>/dev/null || true
```

**Breakdown:**
1. Try to enable lingering
2. Redirect errors to /dev/null (hide error messages)
3. `|| true` = If it fails, run `true` (which always succeeds)
4. This prevents `set -e` from terminating the script if lingering fails

### Here Documents (Heredoc)

```bash
cat > "$START_SCRIPT" << EOF
#!/bin/bash
# Script content here
x0vncserver -display :0 \
    -rfbport 5900
EOF
```

**Syntax:** `<< DELIMITER`

**What it does:**
- Allows multi-line string input
- Everything between `<< EOF` and `EOF` is treated as input
- Variables are expanded (use `'EOF'` to prevent expansion)

**Example:**
```bash
cat > file.txt << 'EOF'
This is line 1
$HOME is not expanded
EOF
```

vs.

```bash
cat > file.txt << EOF
This is line 1
$HOME is expanded to: $HOME
EOF
```

### Parameter Expansion

```bash
${#missing[@]}      # Array length
${missing[*]}       # All array elements as single string
${missing[@]}       # All array elements as separate strings
$(dirname "$FILE")  # Get directory part of path
$(whoami)           # Get current username
```

**Examples:**
```bash
path="/home/user/file.txt"
$(dirname "$path")   # Returns: /home/user
$(basename "$path")  # Returns: file.txt
```

### Test Operators

```bash
[ -f "$file" ]     # True if file exists and is regular file
[ -d "$dir" ]      # True if directory exists
[ -z "$var" ]      # True if variable is empty
[ -n "$var" ]      # True if variable is not empty
[ -t 2 ]           # True if file descriptor 2 (stderr) is terminal
```

**Example:**
```bash
if [ ! -d "$VNC_DIR" ]; then
    mkdir -p "$VNC_DIR"
fi
```
- `!` = NOT operator
- `[ ! -d "$VNC_DIR" ]` = True if directory does NOT exist
- `mkdir -p` = Create directory and parents if needed

### Command Operators

#### Pipe `|`
```bash
lspci | grep -i vga
```
Sends stdout of first command to stdin of second command.

#### Logical AND `&&`
```bash
command1 && command2
```
Execute command2 only if command1 succeeds (exit code 0).

#### Logical OR `||`
```bash
command1 || command2
```
Execute command2 only if command1 fails (exit code non-zero).

#### Background `&`
```bash
command &
```
Run command in background, return control to shell immediately.

### Find Command

```bash
find /tmp -maxdepth 1 -name "xauth_*" -user $(whoami) 2>/dev/null | head -1
```

**Breakdown:**
- `find /tmp` = Search in /tmp directory
- `-maxdepth 1` = Don't search subdirectories
- `-name "xauth_*"` = Files matching pattern (wildcard)
- `-user $(whoami)` = Only files owned by current user
- `2>/dev/null` = Hide error messages
- `| head -1` = Take only first result

### Chmod (Change Mode)

```bash
chmod 700 "$VNC_DIR"
chmod 600 "$VNC_PASSWD_FILE"
chmod +x "$START_SCRIPT"
```

**Permission numbers (octal):**
- `7` = rwx (read, write, execute) = 4+2+1
- `6` = rw- (read, write) = 4+2+0
- `0` = --- (no permissions)

**Three digits represent:**
1. Owner permissions
2. Group permissions
3. Other users permissions

**Examples:**
- `700` = Owner: rwx, Group: ---, Others: ---
- `600` = Owner: rw-, Group: ---, Others: ---
- `755` = Owner: rwx, Group: r-x, Others: r-x

**Symbolic mode:**
```bash
chmod +x file     # Add execute permission for all
chmod u+x file    # Add execute for user (owner) only
chmod go-w file   # Remove write for group and others
```

---

## Installation & Usage

### Prerequisites

- openSUSE Tumbleweed (or compatible Linux distribution)
- X11 display server (not Wayland)
- sudo access
- Active network connection

### Step 1: Download the Script

Save the script to your home directory:

```bash
nano ~/vnc-manager.sh
```

Paste the script content, then save (Ctrl+X, Y, Enter).

### Step 2: Make Executable

```bash
chmod +x ~/vnc-manager.sh
```

### Step 3: Run the Script

```bash
~/vnc-manager.sh
```

### Menu Options Explained

#### 1) Full Setup (First Time Setup)
**What it does:**
- Checks/installs TigerVNC
- Creates all directories and config files
- Prompts for VNC password
- Configures firewall
- Starts VNC server
- Enables auto-start on boot

**When to use:** First time setting up VNC

**What you'll need:**
- Sudo password (for firewall)
- VNC password (6-8 characters)

#### 2) Set/Change VNC Password
**What it does:**
- Prompts for new VNC password
- Updates password file

**When to use:** 
- Forgot your password
- Want to change password for security

#### 3) Configure Firewall
**What it does:**
- Opens port 5900 in firewall
- Reloads firewall rules

**When to use:**
- After fresh firewall configuration
- If connections are blocked

#### 4-6) Start/Stop/Restart Service
**What they do:**
- Control VNC server process
- Don't affect auto-start setting

**When to use:**
- After making configuration changes (restart)
- To temporarily disable access (stop)
- To start after stopping (start)

#### 7-8) Enable/Disable Service
**What they do:**
- Control auto-start on boot
- Enable also starts service now
- Disable also stops service now

**When to use:**
- Enable: Want VNC to start automatically
- Disable: Don't want automatic start

#### 9) Show Service Status
**What it does:**
- Shows systemd service status
- Shows if listening on port 5900

**When to use:**
- Troubleshooting connection issues
- Verify server is running

#### 10) Show Service Logs
**What it does:**
- Displays last 50 lines of VNC server logs

**When to use:**
- Troubleshooting errors
- Checking connection attempts

#### 11) Show Connection Info
**What it does:**
- Displays your IP address
- Shows VNC port
- Provides Remmina configuration details

**When to use:**
- Setting up client connection
- Sharing access info with others

#### 12) Show System Information
**What it does:**
- Displays hostname and IP
- Shows graphics hardware
- Displays desktop environment

**When to use:**
- Verify hardware detection
- Check if using X11 or Wayland

#### 13) Complete Uninstall
**What it does:**
- Stops and removes VNC service
- Deletes all configuration files
- Removes startup scripts
- Disables user lingering

**What it keeps:**
- TigerVNC package (must remove manually)
- Firewall rules (for security)

**When to use:**
- Starting over with fresh setup
- Removing VNC completely

---

## Connecting from Client

### Using Remmina (Recommended)

1. **Open Remmina**
   ```bash
   remmina
   ```

2. **Create New Connection**
   - Click the `+` button

3. **Configure Connection**
   - **Name:** Tumbleweed Desktop (or your choice)
   - **Protocol:** VNC - Virtual Network Computing
   - **Server:** `192.168.0.39:5900` (use your server's IP)
   - **Username:** (leave blank)
   - **Password:** Your VNC password
   - **Color Depth:** True color (24 bpp)
   - **Quality:** Medium or Good

4. **Advanced Settings (Optional)**
   - Enable compression: ✓ (for better performance)
   - Disable encryption: ✓ (if using basic VncAuth)

5. **Save and Connect**

### Using Command Line VNC Viewer

```bash
vncviewer 192.168.0.39:5900
```

### From Windows

Use **TigerVNC Viewer** or **RealVNC Viewer**:
1. Download and install VNC viewer
2. Enter: `192.168.0.39:5900`
3. Enter password when prompted

---

## Troubleshooting

### Black Screen

**Causes:**
1. Wrong XAUTHORITY path
2. Using Wayland instead of X11
3. Desktop environment not starting

**Solutions:**

**Check display server:**
```bash
echo $XDG_SESSION_TYPE
```
Should show `x11`, not `wayland`.

**If Wayland, switch to X11:**
1. Log out
2. At login screen, click gear icon
3. Select "Plasma (X11)" or "GNOME on Xorg"
4. Log back in
5. Restart VNC service

**Verify XAUTHORITY:**
```bash
echo $XAUTHORITY
ls -l $XAUTHORITY
```

**Manual fix:**
```bash
systemctl --user stop x0vncserver
export XAUTHORITY=$(echo $XAUTHORITY)
x0vncserver -display :0 -rfbport 5900 -PasswordFile ~/.vnc/passwd -localhost no
```

### Cannot Connect

**Possible causes:**
1. Firewall blocking
2. Wrong IP address
3. VNC server not running

**Check firewall:**
```bash
sudo firewall-cmd --list-all | grep 5900
```

Should show: `ports: 5900/tcp`

**Open firewall manually:**
```bash
sudo firewall-cmd --permanent --add-port=5900/tcp
sudo firewall-cmd --reload
```

**Check VNC is running:**
```bash
systemctl --user status x0vncserver
netstat -tulpn | grep 5900
```

**Find your IP address:**
```bash
hostname -I
ip addr show
```

### Service Fails to Start

**Check logs:**
```bash
journalctl --user -u x0vncserver.service -n 50
```

**Common errors:**

**"Unable to open display"**
- XAUTHORITY problem
- Run option 13 (Uninstall), then option 1 (Full Setup)

**"Address already in use"**
- Another process using port 5900
- Kill it: `pkill x0vncserver`

**"Permission denied"**
- Password file wrong permissions
- Fix: `chmod 600 ~/.vnc/passwd`

### Service Won't Auto-Start on Boot

**Check if enabled:**
```bash
systemctl --user status x0vncserver
```

Should show: `enabled`

**Check lingering:**
```bash
loginctl show-user $USER | grep Linger
```

Should show: `Linger=yes`

**Enable manually:**
```bash
systemctl --user enable x0vncserver
loginctl enable-linger $USER
```

### Password Not Working

**Reset password:**
```bash
~/vnc-manager.sh
# Select option 2
```

Or manually:
```bash
vncpasswd ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
```

### Slow Performance

**Reduce color depth in Remmina:**
- Change Color Depth to: High color (16 bpp) or 256 colors (8 bpp)

**Reduce quality:**
- Change Quality to: Poor or Medium

**Enable compression:**
- Check "Enable compression" in Advanced settings

**Check network:**
```bash
ping [server-ip]
```

---

## Advanced Configuration

### Custom VNC Options

Edit `~/start-vnc.sh` to add custom options:

```bash
x0vncserver -display :0 \
    -rfbport 5900 \
    -PasswordFile "$HOME/.vnc/passwd" \
    -localhost no \
    -AlwaysShared \
    -MaxProcessorUsage 50 \      # Limit CPU usage
    -Log *:stderr:30              # More verbose logging
```

### Different Port

To use a different port:

1. Edit `~/start-vnc.sh`:
   ```bash
   -rfbport 5901  # Instead of 5900
   ```

2. Open firewall:
   ```bash
   sudo firewall-cmd --permanent --add-port=5901/tcp
   sudo firewall-cmd --reload
   ```

3. Restart service:
   ```bash
   systemctl --user restart x0vncserver
   ```

4. Connect to: `server-ip:5901`

### Security Hardening

**1. Use SSH Tunnel (Most Secure)**

On client machine:
```bash
ssh -L 5900:localhost:5900 user@server-ip
```

Then connect VNC to: `localhost:5900`

This encrypts all VNC traffic through SSH.

**2. Limit to Local Network**

Edit `/etc/hosts.allow`:
```
x0vncserver: 192.168.0.0/24
```

Edit `/etc/hosts.deny`:
```
x0vncserver: ALL
```

**3. Use VeNCrypt (TLS encryption)**

Requires certificates - beyond scope of this guide.

---

## Files Created by Script

### Configuration Files

| File | Purpose | Permissions |
|------|---------|-------------|
| `~/.vnc/passwd` | VNC password (encrypted) | 600 (rw-------) |
| `~/.vnc/config` | VNC configuration | 644 (rw-r--r--) |
| `~/start-vnc.sh` | Startup script | 755 (rwxr-xr-x) |
| `~/.config/systemd/user/x0vncserver.service` | Systemd service | 644 (rw-r--r--) |

### What Each File Contains

**~/.vnc/passwd:**
- Binary file (not human-readable)
- Contains encrypted VNC password
- Created by `vncpasswd` command

**~/.vnc/config:**
```
securitytypes=vncauth
geometry=1920x1080
localhost=no
alwaysshared
```

**~/start-vnc.sh:**
```bash
#!/bin/bash
# Finds XAUTHORITY
# Starts x0vncserver with detected graphics options
```

**~/.config/systemd/user/x0vncserver.service:**
```ini
[Unit]
Description=x0vncserver - VNC Server for X Display
After=graphical.target

[Service]
Type=simple
ExecStart=/home/username/start-vnc.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

---

## Frequently Asked Questions

### Q: Will this work on other distributions?

**A:** Mostly yes, with modifications:
- **Debian/Ubuntu**: Change `zypper` to `apt`
- **Fedora/RHEL**: Change `zypper` to `dnf`
- **Arch**: Change `zypper` to `pacman`

The script attempts to detect your package manager automatically.

### Q: Can I use this with Wayland?

**A:** No. x0vncserver requires X11. You must:
1. Switch to X11 session
2. Or use alternative like `wayvnc` (requires different setup)

### Q: Does this work with multiple monitors?

**A:** Yes, x0vncserver shares all monitors on display :0. The VNC client will show your entire desktop spanning all monitors.

### Q: Can multiple people connect simultaneously?

**A:** Yes, with the `-AlwaysShared` flag (enabled by default in this script). All connections see the same desktop and can control it.

### Q: Is this secure?

**A:** Basic security:
- Password protected
- Firewall configured

For better security:
- Use SSH tunnel
- Use VeNCrypt (TLS encryption)
- Restrict to local network only

### Q: Will this work over the internet?

**A:** Yes, but requires:
1. Port forwarding on your router (5900 → your computer)
2. Your public IP address or dynamic DNS
3. Strong password
4. Preferably SSH tunnel

Not recommended without SSH tunnel due to security risks.

### Q: What's the difference between TigerVNC and x11vnc?

**A:**
- **TigerVNC**: Modern, actively maintained, better performance
- **x11vnc**: Older, deprecated, but had good features

This script uses TigerVNC's `x0vncserver` component.

### Q: Can I run this on a headless server?

**A:** No. x0vncserver requires an existing X11 display. For headless servers, use `Xvnc` to create a virtual display (different setup).

---

## Complete Command Reference

### Systemd Commands

```bash
# User service commands
systemctl --user start x0vncserver      # Start service
systemctl --user stop x0vncserver       # Stop service
systemctl --user restart x0vncserver    # Restart service
systemctl --user status x0vncserver     # Check status
systemctl --user enable x0vncserver     # Enable auto-start
systemctl --user disable x0vncserver    # Disable auto-start

# View logs
journalctl --user -u x0vncserver        # All logs
journalctl --user -u x0vncserver -f     # Follow logs (live)
journalctl --user -u x0vncserver -n 50  # Last 50 lines

# Reload systemd
systemctl --user daemon-reload          # After editing service file
```

### Firewall Commands

```bash
# Add rules
sudo firewall-cmd --permanent --add-port=5900/tcp
sudo firewall-cmd --permanent --add-port=5900-5910/tcp  # Range
sudo firewall-cmd --permanent --add-service=vnc-server

# Remove rules
sudo firewall-cmd --permanent --remove-port=5900/tcp
sudo firewall-cmd --permanent --remove-service=vnc-server

# Apply changes
sudo firewall-cmd --reload

# View configuration
sudo firewall-cmd --list-all
sudo firewall-cmd --list-ports
sudo firewall-cmd --list-services
```

### VNC Commands

```bash
# Set password
vncpasswd ~/.vnc/passwd

# Start x0vncserver manually
x0vncserver -display :0 -rfbport 5900 -Passwor
