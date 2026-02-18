# VNC Server Setup Guide for openSUSE Tumbleweed
### Why the Original Script Was Changed, How Xauth Works, and Full Setup Instructions

---

## Table of Contents

1. [Why the Original Script Was Changed](#why-the-original-script-was-changed)
2. [How Xauth Works](#how-xauth-works)
3. [Why Xauth Caused Our Problem](#why-xauth-caused-our-problem)
4. [The Role of SELinux](#the-role-of-selinux)
5. [The Solution: KDE Autostart](#the-solution-kde-autostart)
6. [How the Autostart File Works](#how-the-autostart-file-works)
7. [How Enable and Disable Service Work](#how-enable-and-disable-service-work)
8. [Full Setup From Scratch](#full-setup-from-scratch)
9. [Files Created and Their Roles](#files-created-and-their-roles)
10. [Dependencies](#dependencies)
11. [Troubleshooting Reference](#troubleshooting-reference)

---

## Why the Original Script Was Changed

The original script used a **systemd user service** to start x0vncserver automatically at boot. This is a standard and normally reliable approach — the service file lived at:

```
~/.config/systemd/user/x0vncserver.service
```

However, on this system (openSUSE Tumbleweed with SDDM and KDE Plasma), the service failed every time after a reboot with this error:

```
Authorization required, but no authorization protocol specified
x0vncserver: Unable to open display ":0"
```

The root cause was a chain of three overlapping problems:

1. **Xauth** — the X display authentication system — stores its credentials in a file whose location changes on every boot.
2. The systemd user service starts too early, before the graphical session is fully established, and cannot find or read that file.
3. **SELinux** is set to enforcing mode on this system, which blocked every attempt to copy the credentials across security contexts (from the SDDM process to the user session).

The solution was to abandon the systemd service entirely and use **KDE Autostart** instead, which launches x0vncserver from inside the already-authenticated graphical session — bypassing all three problems at once.

---

## How Xauth Works

### What is Xauth?

`xauth` (X Authority) is the authentication system used by the X Window System to control which clients are allowed to connect to an X display.

When you log into a graphical desktop, the X server starts up and generates a secret random token called a **magic cookie**. This cookie is stored in a special file — the **Xauthority file**. Any program that wants to draw windows or interact with the display must present this cookie to the X server. If it cannot, the X server rejects the connection with the message:

```
Authorization required, but no authorization protocol specified
```

### Where is the Xauthority File?

This is where things get complicated. The location is not fixed — it depends on your display manager. On this system, SDDM (the Simple Desktop Display Manager) manages the X session and stores the file here:

```
/run/sddm/xauth_<random_suffix>
```

The random suffix (e.g. `xauth_ozzzRq`) is generated fresh on every single boot. There is no way to know in advance what it will be called.

Additionally, the `/run/sddm/` directory has very restrictive permissions:

```
drwx--x--x.  2 root root
-rw-------.  1 sddm sddm  xauth_ozzzRq
```

The file is owned by the `sddm` user and readable only by that user. Even root cannot read it in a normal security context when SELinux is enforcing.

### How Xauth Credentials Are Used

When a program like `x0vncserver` starts, it checks the environment variable `XAUTHORITY` to find the credentials file. If this variable points to the right file and the file is readable, authentication succeeds. If the variable is empty, wrong, or the file is unreadable, it fails.

In an interactive desktop session, your display manager (SDDM) sets `XAUTHORITY` correctly in your environment automatically. This is why x0vncserver works perfectly when you run it manually from a terminal — your session already has everything set up.

---

## Why Xauth Caused Our Problem

When systemd starts a user service at boot, it runs in a **clean environment** — it does not inherit your interactive session's environment variables. So `XAUTHORITY` is either empty or pointing nowhere useful.

We attempted several workarounds:

### Attempt 1: Find the SDDM xauth file dynamically

We tried to locate the file using `find`:

```bash
export XAUTHORITY=$(find /run/sddm -name "xauth_*" | head -1)
```

This failed because `/run/sddm/` denies access to non-root users:

```
cannot open directory '/run/sddm/': Permission denied
```

### Attempt 2: A system-level service to copy the cookie

We created a root-level systemd service (`sddm-xauth-copy.service`) to read the SDDM xauth file and merge it into `~/.Xauthority` using `su - mark`. This failed with exit code 126 when run as an inline command, and then failed again as a script because **SELinux** blocked the cross-context file access.

### Attempt 3: Merge via a helper script

Even with a dedicated script at `/usr/local/bin/sddm-xauth-copy.sh`, SELinux continued to block access. The security context of the SDDM xauth file is restricted to the `sddm_t` domain, and processes outside that domain — even root — cannot read it when SELinux is in enforcing mode.

---

## The Role of SELinux

SELinux (Security-Enhanced Linux) adds a mandatory access control layer on top of standard Linux permissions. It assigns a **security context** (or label) to every file and process, and enforces rules about which contexts can interact with which.

On this system:

```bash
sudo getenforce
# Enforcing
```

The SDDM xauth file carries an SELinux label restricting it to the `sddm_t` security domain. Any attempt by a process in a different domain — including a root-level systemd service — to read that file is denied at the SELinux level, regardless of standard Unix permissions.

Fighting this would have required writing custom SELinux policy modules, which is complex and risky. The KDE Autostart approach sidesteps the problem entirely.

---

## The Solution: KDE Autostart

KDE Plasma's autostart mechanism launches applications **after** the graphical session is fully established. At that point:

- The X server is running
- SDDM has already set `XAUTHORITY` correctly in the session environment
- All environment variables are populated
- SELinux context is the user's own session context

Because x0vncserver launches as part of your own session, it inherits `XAUTHORITY` naturally and connects to the display without any special handling.

This is exactly equivalent to opening a terminal and typing `x0vncserver ...` — the only difference is KDE does it for you automatically at login.

---

## How the Autostart File Works

The autostart entry is a standard `.desktop` file placed in:

```
~/.config/autostart/x0vncserver.desktop
```

### The File Contents

```ini
[Desktop Entry]
Type=Application
Name=x0vncserver
Comment=VNC Server for X Display
Exec=x0vncserver -display :0 -rfbport 5900 -PasswordFile /home/mark/.vnc/passwd -localhost no -AlwaysShared
Hidden=false
NoDisplay=false
X-KDE-Autostart-enabled=true
```

### What Each Line Means

| Key | Purpose |
|-----|---------|
| `Type=Application` | Tells KDE this is a program to launch, not a link or directory |
| `Name=x0vncserver` | Display name shown in KDE's autostart settings panel |
| `Comment=...` | Description shown in the settings panel |
| `Exec=...` | The exact command to run at login |
| `Hidden=false` | When `true`, KDE ignores this entry entirely (used to disable without deleting) |
| `NoDisplay=false` | When `true`, hides it from the settings panel UI but still runs it |
| `X-KDE-Autostart-enabled=true` | KDE-specific flag; when `false`, disables the entry |

### The Exec Command Explained

```bash
x0vncserver -display :0 -rfbport 5900 -PasswordFile /home/mark/.vnc/passwd -localhost no -AlwaysShared
```

| Flag | Meaning |
|------|---------|
| `-display :0` | Connect to the primary X display |
| `-rfbport 5900` | Listen on the standard VNC port |
| `-PasswordFile ...` | Use the stored VNC password file for authentication |
| `-localhost no` | Accept connections from other machines (not just localhost) |
| `-AlwaysShared` | Allow multiple VNC clients to connect simultaneously |

### When Does it Run?

KDE processes all `.desktop` files in `~/.config/autostart/` immediately after the desktop environment finishes loading — typically within a few seconds of reaching the login screen. The order is not guaranteed among autostart entries, but since x0vncserver only needs the X display (which is already running at this point), ordering does not matter here.

---

## How Enable and Disable Service Work

Unlike the old systemd approach, there is no daemon to enable or disable. Instead, the script manipulates the `Hidden` and `X-KDE-Autostart-enabled` fields in the `.desktop` file.

### Enabling

```bash
sed -i 's/^Hidden=.*/Hidden=false/' "$AUTOSTART_FILE"
sed -i 's/^X-KDE-Autostart-enabled=.*/X-KDE-Autostart-enabled=true/' "$AUTOSTART_FILE"
```

This edits the file in-place, setting both flags to their active state. KDE reads these values fresh at each login, so the change takes effect at the next reboot or logout/login without any daemon reload needed.

### Disabling

```bash
sed -i 's/^Hidden=.*/Hidden=true/' "$AUTOSTART_FILE"
sed -i 's/^X-KDE-Autostart-enabled=.*/X-KDE-Autostart-enabled=false/' "$AUTOSTART_FILE"
```

Setting `Hidden=true` causes KDE to completely ignore the entry. The file remains in place so it can be re-enabled at any time — nothing is deleted.

### Starting and Stopping (Current Session)

For the current session, the script uses direct process management:

- **Start:** `nohup x0vncserver ... > /tmp/x0vncserver.log 2>&1 &`
  - `nohup` prevents the process from dying when the terminal closes
  - `&` sends it to the background
  - Output is logged to `/tmp/x0vncserver.log`

- **Stop:** `pkill -x x0vncserver`
  - `-x` matches the process name exactly, avoiding accidentally killing unrelated processes

- **Status:** `pgrep -x x0vncserver`
  - Returns the PID if running, nothing if not

---

## Full Setup From Scratch

Follow these steps on a fresh openSUSE Tumbleweed installation.

### Step 1: Install TigerVNC

```bash
sudo zypper install tigervnc
```

Verify it installed correctly:

```bash
which x0vncserver
# /usr/bin/x0vncserver
```

### Step 2: Confirm You Are Running X11 (not Wayland)

x0vncserver requires X11. Check your session type:

```bash
echo $XDG_SESSION_TYPE
# Should output: x11
```

If it outputs `wayland`, you need to switch to an X11 session. At the SDDM login screen, click the session selector in the bottom-left corner and choose **Plasma (X11)** instead of **Plasma (Wayland)**.

### Step 3: Download and Prepare the Script

```bash
chmod +x vnc_setup_manager.sh
```

### Step 4: Run Full Setup

```bash
./vnc_setup_manager.sh
```

Select option **1) Full Setup** from the menu. The script will:

1. Confirm TigerVNC is installed
2. Create `~/.vnc/` directory
3. Prompt you to set a VNC password
4. Create `~/.vnc/config`
5. Create `~/.config/autostart/x0vncserver.desktop`
6. Configure the firewall (if firewalld is running)
7. Start x0vncserver immediately for the current session

### Step 5: Test the Connection

From another machine, connect using any VNC client (Remmina, TigerVNC Viewer, RealVNC, etc.):

```
Host: <your-ip-address>:5900
Password: <the VNC password you set>
```

Find your IP address with:

```bash
hostname -I | awk '{print $1}'
```

### Step 6: Reboot and Verify

```bash
sudo reboot
```

After logging back in, wait about 10 seconds, then try connecting again. x0vncserver should have started automatically via KDE autostart.

You can also verify it is running with:

```bash
pgrep -x x0vncserver
```

---

## Files Created and Their Roles

| File | Purpose |
|------|---------|
| `~/.vnc/` | Directory for all VNC configuration |
| `~/.vnc/passwd` | Encrypted VNC password file. Created by `vncpasswd`. Permissions must be `600` (owner read/write only). |
| `~/.vnc/config` | VNC server configuration. Sets security type, geometry, and sharing options. |
| `~/.config/autostart/x0vncserver.desktop` | KDE autostart entry. Tells KDE to launch x0vncserver at every login. |
| `/tmp/x0vncserver.log` | Runtime log file. Created when the script starts x0vncserver. Useful for troubleshooting. Cleared on reboot. |

### ~/.vnc/config Contents

```ini
# VNC Server Configuration
securitytypes=vncauth
geometry=1920x1080
localhost=no
alwaysshared
```

| Setting | Meaning |
|---------|---------|
| `securitytypes=vncauth` | Use password authentication |
| `geometry=1920x1080` | Default resolution hint |
| `localhost=no` | Allow remote connections |
| `alwaysshared` | Multiple clients can connect simultaneously |

---

## Dependencies

| Package | What it Provides | Install Command |
|---------|-----------------|-----------------|
| `tigervnc` | `x0vncserver`, `vncpasswd`, `vncviewer` | `sudo zypper install tigervnc` |
| `firewalld` | Firewall management (optional) | Usually pre-installed |
| `lspci` (pciutils) | GPU detection in the script | `sudo zypper install pciutils` |
| `ss` (iproute2) | Port status checking | Usually pre-installed |
| KDE Plasma | Autostart mechanism | Pre-installed on KDE systems |
| X11 session | Required by x0vncserver | Select at SDDM login screen |

### Checking All Dependencies at Once

```bash
for cmd in x0vncserver vncpasswd lspci ss pgrep pkill; do
    if command -v "$cmd" &>/dev/null; then
        echo "✓ $cmd found"
    else
        echo "✗ $cmd MISSING"
    fi
done
```

---

## Troubleshooting Reference

### VNC connects but shows a black screen
- Usually means x0vncserver started before the desktop finished loading.
- Wait 10-15 seconds after login and try reconnecting.

### Cannot connect at all after reboot
```bash
# Check if x0vncserver is running
pgrep -x x0vncserver

# Check if port 5900 is open
ss -tulpn | grep 5900

# Check logs
cat /tmp/x0vncserver.log

# Start it manually if needed
x0vncserver -display :0 -rfbport 5900 -PasswordFile ~/.vnc/passwd -localhost no -AlwaysShared &
```

### Autostart is not working
```bash
# Verify the autostart file exists and looks correct
cat ~/.config/autostart/x0vncserver.desktop

# Check Hidden and X-KDE-Autostart-enabled are both set to false/true respectively
# If the file is missing, run the script and choose option 7 (Enable Autostart)
```

### Firewall blocking connections
```bash
# Check firewall status
sudo firewall-cmd --list-ports

# Open port 5900 manually if needed
sudo firewall-cmd --permanent --add-port=5900/tcp
sudo firewall-cmd --reload
```

### Check your session type
```bash
echo $XDG_SESSION_TYPE
# Must be x11 — if wayland, switch at the login screen
```

### Password file issues
```bash
# Recreate the password file
vncpasswd ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
```
