#!/bin/bash

# VNC Server Setup and Manager for openSUSE Tumbleweed
# Supports x0vncserver for sharing existing desktop

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
VNC_PORT=5900
VNC_DIR="$HOME/.vnc"
VNC_PASSWD_FILE="$VNC_DIR/passwd"
SERVICE_FILE="$HOME/.config/systemd/user/x0vncserver.service"
START_SCRIPT="$HOME/start-vnc.sh"

print_msg() {
    local color="$1"
    local msg="$2"
    
    
    # What $1 and $2 are (exactly)
	# Inside any shell function or script:
	# $1 = first positional parameter
	# $2 = second positional parameter
	# They are populated automatically by the shell from how the function (or script) is called"
    
    # In this case  print_msg "$BLUE" called from detect_graphics
    
    
    # If stderr is a terminal, keep colours; otherwise strip them
    if [ -t 2 ]; then
        echo -e "${color}${msg}${NC}" >&2
    else
        echo "$msg" >&2
    fi
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_msg "$RED" "Please do not run this script as root!"
        exit 1
    fi
}

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
        print_msg "$YELLOW" "Using optimized settings for older Intel graphics"

    elif echo "$gpu_info" | grep -qi "intel"; then
        gpu_type="Intel"
        vnc_options="-AlwaysShared"
        print_msg "$GREEN" "Detected: Intel graphics"

    elif echo "$gpu_info" | grep -qi "nvidia"; then
        gpu_type="NVIDIA"
        vnc_options="-AlwaysShared"
        print_msg "$GREEN" "Detected: NVIDIA graphics"

    elif echo "$gpu_info" | grep -qi "amd\|radeon"; then
        gpu_type="AMD/Radeon"
        vnc_options="-AlwaysShared"
        print_msg "$GREEN" "Detected: AMD/Radeon graphics"

    else
        gpu_type="Unknown"
        vnc_options="-AlwaysShared"
        print_msg "$YELLOW" "Graphics type unknown, using default settings"
    fi

    # CRITICAL: only this goes to stdout
    echo "$vnc_options"
}


# Function to auto-install TigerVNC
auto_install_tigervnc() {
    print_msg "$BLUE" "Checking for TigerVNC installation..."
    
    if command -v x0vncserver &> /dev/null; then
        print_msg "$GREEN" "TigerVNC is already installed!"
        return 0
    fi
    
    print_msg "$YELLOW" "TigerVNC is not installed."
    read -p "Would you like to install it now? (y/n): " install_choice
    
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        print_msg "$BLUE" "Installing TigerVNC..."
        
        # Detect package manager
        if command -v zypper &> /dev/null; then
            sudo zypper install -y tigervnc
        elif command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y tigervnc-standalone-server
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y tigervnc-server
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm tigervnc
        else
            print_msg "$RED" "Could not detect package manager. Please install TigerVNC manually."
            exit 1
        fi
        
        if [ $? -eq 0 ]; then
            print_msg "$GREEN" "TigerVNC installed successfully!"
        else
            print_msg "$RED" "Failed to install TigerVNC"
            exit 1
        fi
    else
        print_msg "$RED" "TigerVNC is required. Exiting."
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    print_msg "$BLUE" "Checking dependencies..."
    
    # First check if TigerVNC is installed, if not offer to install
    auto_install_tigervnc
    
    local deps=("x0vncserver" "vncpasswd" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_msg "$RED" "Missing dependencies: ${missing[*]}"
        print_msg "$YELLOW" "This should not happen after TigerVNC installation."
        print_msg "$YELLOW" "Please check your installation."
        exit 1
    fi
    
    print_msg "$GREEN" "All dependencies satisfied!"
}

# Function to create VNC directory
create_vnc_dir() {
    if [ ! -d "$VNC_DIR" ]; then
        print_msg "$BLUE" "Creating VNC directory..."
        mkdir -p "$VNC_DIR"
        chmod 700 "$VNC_DIR"
        print_msg "$GREEN" "VNC directory created: $VNC_DIR"
    else
        print_msg "$GREEN" "VNC directory already exists: $VNC_DIR"
    fi
}

# Function to set VNC password
set_vnc_password() {
    print_msg "$BLUE" "Setting VNC password..."
    echo ""
    print_msg "$YELLOW" "You will be prompted to enter a VNC password (6-8 characters recommended)"
    echo ""
    
    vncpasswd "$VNC_PASSWD_FILE"
    
    if [ $? -eq 0 ]; then
        chmod 600 "$VNC_PASSWD_FILE"
        print_msg "$GREEN" "VNC password set successfully!"
    else
        print_msg "$RED" "Failed to set VNC password"
        return 1
    fi
}

# Function to create VNC config file
create_vnc_config() {
    print_msg "$BLUE" "Creating VNC configuration file..."
    
    cat > "$VNC_DIR/config" << 'EOF'
# VNC Server Configuration
securitytypes=vncauth
geometry=1920x1080
localhost=no
alwaysshared
EOF
    
    chmod 644 "$VNC_DIR/config"
    print_msg "$GREEN" "VNC config created: $VNC_DIR/config"
}



# Function to create startup script
create_startup_script() {
    print_msg "$BLUE" "Creating VNC startup script..."
    
    # Detect graphics hardware and get optimized options
    local vnc_opts=$(detect_graphics)
    
    # Create the start-vnc.sh script without any color codes
    cat > "$START_SCRIPT" << 'OUTER_EOF'
#!/bin/bash

# Get current XAUTHORITY (it changes on each login)
if [ -z "$XAUTHORITY" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
fi

# Start x0vncserver with hardware-optimized settings
x0vncserver -display :0 \
    -rfbport 5900 \
    -PasswordFile "$HOME/.vnc/passwd" \
    -localhost no \
    -AlwaysShared \
    2>&1 | logger -t x0vncserver
OUTER_EOF
    
    # Now replace the placeholder with actual vnc_opts
    sed -i "s/-AlwaysShared/$vnc_opts/" "$START_SCRIPT"
    
    chmod +x "$START_SCRIPT"
    print_msg "$GREEN" "Startup script created: $START_SCRIPT"
    print_msg "$BLUE" "Configured with optimized settings for your graphics hardware"
    
    cat "$START_SCRIPT"
}

# Function to create systemd service
create_systemd_service() {
    print_msg "$BLUE" "Creating systemd user service..."
    
    # Create systemd user directory if it doesn't exist
    mkdir -p "$(dirname "$SERVICE_FILE")"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=x0vncserver - VNC Server for X Display
After=graphical.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'export DISPLAY=:0; if [ -n "\$XAUTHORITY" ]; then export XAUTHORITY="\$XAUTHORITY"; fi; $START_SCRIPT'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    
    print_msg "$GREEN" "Systemd service created: $SERVICE_FILE"
}

# Function to configure firewall
configure_firewall() {
    print_msg "$BLUE" "Configuring firewall..."
    
    # Check if firewalld is running
    if ! systemctl is-active --quiet firewalld; then
        print_msg "$YELLOW" "Firewalld is not running, skipping firewall configuration"
        return 0
    fi
    
    print_msg "$YELLOW" "This requires sudo privileges..."
    
    # Add VNC port
    sudo firewall-cmd --permanent --add-port=5900/tcp &> /dev/null
    sudo firewall-cmd --reload &> /dev/null
    
    if [ $? -eq 0 ]; then
        print_msg "$GREEN" "Firewall configured: Port 5900 opened"
    else
        print_msg "$RED" "Failed to configure firewall"
    fi
}

# Function to start VNC service
start_service() {
    print_msg "$BLUE" "Starting VNC service..."
    
    # Reload systemd to pick up any changes
    systemctl --user daemon-reload
    
    systemctl --user start x0vncserver.service
    
    if [ $? -eq 0 ]; then
        print_msg "$GREEN" "VNC service started successfully!"
        sleep 2
        show_service_status
    else
        print_msg "$RED" "Failed to start VNC service"
        print_msg "$YELLOW" "Check logs with: journalctl --user -u x0vncserver.service"
    fi
}

# Function to stop VNC service
stop_service() {
    print_msg "$BLUE" "Stopping VNC service..."
    
    systemctl --user stop x0vncserver.service
    
    if [ $? -eq 0 ]; then
        print_msg "$GREEN" "VNC service stopped"
    else
        print_msg "$RED" "Failed to stop VNC service"
    fi
}

# Function to restart VNC service
restart_service() {
    print_msg "$BLUE" "Restarting VNC service..."
    
    # Reload systemd to pick up any changes
    systemctl --user daemon-reload
    
    systemctl --user restart x0vncserver.service
    
    if [ $? -eq 0 ]; then
        print_msg "$GREEN" "VNC service restarted successfully!"
        sleep 2
        show_service_status
    else
        print_msg "$RED" "Failed to restart VNC service"
    fi
}

# Function to enable VNC service
enable_service() {
    print_msg "$BLUE" "Enabling VNC service (auto-start on login)..."
    
    # Enable lingering for the user (allows service to run without active session)
    print_msg "$BLUE" "Enabling user lingering..."
    loginctl enable-linger "$USER"
    
    systemctl --user enable x0vncserver.service
    
    if [ $? -eq 0 ]; then
        print_msg "$GREEN" "VNC service enabled (will start automatically on login)"
    else
        print_msg "$RED" "Failed to enable VNC service"
    fi
}

# Function to disable VNC service
disable_service() {
    print_msg "$BLUE" "Disabling VNC service..."
    
    systemctl --user disable x0vncserver.service
    
    if [ $? -eq 0 ]; then
        print_msg "$GREEN" "VNC service disabled (will not start automatically)"
    else
        print_msg "$RED" "Failed to disable VNC service"
    fi
}

# Function to show system information
show_system_info() {
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "System Information"
    print_msg "$GREEN" "═════════════════════════"
    echo ""
    
    # Hostname
    print_msg "$BLUE" "Hostname: $(hostname)"
    
    # IP Address
    ip_addr=$(hostname -I | awk '{print $1}')
    print_msg "$BLUE" "IP Address: $ip_addr"
    
    # Graphics Hardware
    print_msg "$BLUE" "Graphics Hardware:"
    lspci | grep -i vga | sed 's/^/  /'
    
    # OpenGL Renderer (if available)
    if command -v glxinfo &> /dev/null; then
        gl_renderer=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
        if [ -n "$gl_renderer" ]; then
            print_msg "$BLUE" "OpenGL Renderer: $gl_renderer"
        fi
    fi
    
    # Display Server
    if [ -n "$WAYLAND_DISPLAY" ]; then
        print_msg "$YELLOW" "Display Server: Wayland (Note: VNC requires X11)"
    else
        print_msg "$GREEN" "Display Server: X11 (Compatible with VNC)"
    fi
    
    # Desktop Environment
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_msg "$BLUE" "Desktop Environment: $XDG_CURRENT_DESKTOP"
    fi
    
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    echo ""
}

# Function to uninstall VNC
uninstall_vnc() {
    echo ""
    print_msg "$RED" "═════════════════════════"
    print_msg "$RED" "COMPLETE UNINSTALL"
    print_msg "$RED" "═════════════════════════"
    echo ""
    print_msg "$YELLOW" "This will remove all VNC configuration and services."
    print_msg "$YELLOW" "The TigerVNC package will NOT be removed."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        print_msg "$GREEN" "Uninstall cancelled."
        return
    fi
    
    echo ""
    print_msg "$BLUE" "Starting uninstallation..."
    echo ""
    
    # Stop and disable service
    print_msg "$BLUE" "Stopping and disabling VNC service..."
    systemctl --user stop x0vncserver.service 2>/dev/null || true
    systemctl --user disable x0vncserver.service 2>/dev/null || true
    
    # Kill any running VNC processes
    print_msg "$BLUE" "Killing any running VNC processes..."
    pkill -9 x0vncserver 2>/dev/null || true
    pkill -9 Xvnc 2>/dev/null || true
    
    # Remove systemd service file
    if [ -f "$SERVICE_FILE" ]; then
        print_msg "$BLUE" "Removing systemd service file..."
        rm -f "$SERVICE_FILE"
        print_msg "$GREEN" "✓ Removed: $SERVICE_FILE"
    fi
    
    # Reload systemd
    systemctl --user daemon-reload 2>/dev/null || true
    
    # Remove startup script
    if [ -f "$START_SCRIPT" ]; then
        print_msg "$BLUE" "Removing startup script..."
        rm -f "$START_SCRIPT"
        print_msg "$GREEN" "✓ Removed: $START_SCRIPT"
    fi
    
    # Remove VNC directory
    if [ -d "$VNC_DIR" ]; then
        print_msg "$BLUE" "Removing VNC directory..."
        rm -rf "$VNC_DIR"
        print_msg "$GREEN" "✓ Removed: $VNC_DIR"
    fi
    
    # Disable lingering
    print_msg "$BLUE" "Disabling user lingering..."
    loginctl disable-linger "$USER" 2>/dev/null || true
    
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "VNC Uninstallation Complete!"
    print_msg "$GREEN" "═════════════════════════"
    echo ""
    print_msg "$YELLOW" "Optional cleanup:"
    echo ""
    echo "To remove TigerVNC package:"
    echo "  sudo zypper remove tigervnc"
    echo ""
    echo "To remove firewall rules:"
    echo "  sudo firewall-cmd --permanent --remove-port=5900/tcp"
    echo "  sudo firewall-cmd --permanent --remove-port=5900-5910/tcp"
    echo "  sudo firewall-cmd --reload"
    echo ""
    print_msg "$GREEN" "You can now run Full Setup (Option 1) for a clean install."
    echo ""
}

# Function to show service status
show_service_status() {
    print_msg "$BLUE" "VNC Service Status:"
    echo ""
    systemctl --user status x0vncserver.service --no-pager
    echo ""
    
    print_msg "$BLUE" "Network Status:"
    if netstat -tulpn 2>/dev/null | grep -q ":5900"; then
        print_msg "$GREEN" "VNC server is listening on port 5900"
    else
        print_msg "$YELLOW" "VNC server is not listening on port 5900"
    fi
}

# Function to show logs
show_logs() {
    print_msg "$BLUE" "VNC Service Logs (last 50 lines):"
    echo ""
    journalctl --user -u x0vncserver.service -n 50 --no-pager
}

# Function to show connection info
show_connection_info() {
    ip_addr=$(hostname -I | awk '{print $1}')
    
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "VNC Connection Information"
    print_msg "$GREEN" "═════════════════════════"
    echo ""
    print_msg "$BLUE" "Server IP Address: $ip_addr"
    print_msg "$BLUE" "VNC Port: 5900"
    print_msg "$BLUE" "Connection String: $ip_addr:5900"
    echo ""
    print_msg "$YELLOW" "Remmina Configuration:"
    print_msg "$YELLOW" "  Protocol: VNC"
    print_msg "$YELLOW" "  Server: $ip_addr:5900"
    print_msg "$YELLOW" "  Password: (your VNC password)"
    print_msg "$YELLOW" "  Color Depth: True color (24 bpp)"
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    echo ""

    echo ""
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "System Information"
    print_msg "$GREEN" "═════════════════════════"
    echo ""
    
    # Hostname
    print_msg "$BLUE" "Hostname: $(hostname)"
    
    # IP Address
    ip_addr=$(hostname -I | awk '{print $1}')
    print_msg "$BLUE" "IP Address: $ip_addr"
    
    # Graphics Hardware
    print_msg "$BLUE" "Graphics Hardware:"
    lspci | grep -i vga | sed 's/^/  /'
    
    # OpenGL Renderer (if available)
    if command -v glxinfo &> /dev/null; then
        gl_renderer=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
        if [ -n "$gl_renderer" ]; then
            print_msg "$BLUE" "OpenGL Renderer: $gl_renderer"
        fi
    fi
    
    # Display Server
    if [ -n "$WAYLAND_DISPLAY" ]; then
        print_msg "$YELLOW" "Display Server: Wayland (Note: VNC requires X11)"
    else
        print_msg "$GREEN" "Display Server: X11 (Compatible with VNC)"
    fi
    
    # Desktop Environment
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_msg "$BLUE" "Desktop Environment: $XDG_CURRENT_DESKTOP"
    fi
    
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    echo ""

    ip_addr=$(hostname -I | awk '{print $1}')
    
    
}

# Function to perform full setup
full_setup() {
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "Starting Full VNC Setup"
    print_msg "$GREEN" "═════════════════════════"
    echo ""
    
    check_dependencies
    create_vnc_dir
    set_vnc_password
    create_vnc_config
    create_startup_script
    create_systemd_service
    configure_firewall
    enable_service
    start_service
    
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "VNC Setup Complete!"
    print_msg "$GREEN" "═════════════════════════"
    
    show_connection_info
}

# Function to show main menu
show_menu() {
    clear
    echo ""
    print_msg "$GREEN" "═════════════════════════"
    print_msg "$GREEN" "    VNC Server Setup & Manager"
    print_msg "$GREEN" "    for openSUSE Tumbleweed"
    print_msg "$GREEN" "═════════════════════════"
    echo ""
    echo "  Setup & Configuration:"
    echo "    1) Full Setup (First Time Setup)"
    echo "    2) Set/Change VNC Password"
    echo "    3) Configure Firewall"
    echo ""
    echo "  Service Management:"
    echo "    4) Start VNC Service"
    echo "    5) Stop VNC Service"
    echo "    6) Restart VNC Service"
    echo "    7) Enable VNC Service (Auto-start)"
    echo "    8) Disable VNC Service"
    echo ""
    echo "  Uninstall:"
    echo "   13) Complete Uninstall (Clean Removal)"
    echo ""
    echo "  Information & Troubleshooting:"
    echo "    9) Show Service Status"
    echo "   10) Show Service Logs"
    echo "   11) Show Connection Info"
    echo "   12) Show System Information"
    echo ""
    echo "    0) Exit"
    echo ""
    print_msg "$BLUE" "═════════════════════════"
    echo ""
}

# Main program loop
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Select an option: " choice
        echo ""
        
        case $choice in
            1)
                full_setup
                read -p "Press Enter to continue..."
                ;;
            2)
                create_vnc_dir
                set_vnc_password
                read -p "Press Enter to continue..."
                ;;
            3)
                configure_firewall
                read -p "Press Enter to continue..."
                ;;
            4)
                start_service
                read -p "Press Enter to continue..."
                ;;
            5)
                stop_service
                read -p "Press Enter to continue..."
                ;;
            6)
                restart_service
                read -p "Press Enter to continue..."
                ;;
            7)
                enable_service
                read -p "Press Enter to continue..."
                ;;
            8)
                disable_service
                read -p "Press Enter to continue..."
                ;;
            9)
                show_service_status
                read -p "Press Enter to continue..."
                ;;
            10)
                show_logs
                read -p "Press Enter to continue..."
                ;;
            11)
                show_connection_info
                read -p "Press Enter to continue..."
                ;;
            12)
                show_system_info
                read -p "Press Enter to continue..."
                ;;
            13)
                uninstall_vnc
                read -p "Press Enter to continue..."
                ;;
            0)
                print_msg "$GREEN" "Exiting..."
                exit 0
                ;;
            *)
                print_msg "$RED" "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Run main program
main
