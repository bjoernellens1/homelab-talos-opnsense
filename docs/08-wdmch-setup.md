# WDMCH Setup Guide: OpenMediaVault

This guide provides a condensed, step-by-step procedure for repurposing a Western Digital My Cloud Home (WDMCH) device as a powerful OpenMediaVault (OMV) NAS.

## Overview

The WDMCH is a consumer NAS featuring a **Realtek RTD1295 (ARM64)** processor. While it meets the requirements for OMV 8, **OMV 6 (Debian 11)** is the recommended path for stability and community support.

### Hardware Specifications
- **Processor**: Realtek RTD1295 (Quad-core ARM Cortex-A53 @ 1.4GHz)
- **Architecture**: ARM64 (64-bit)
- **RAM**: 1 GB
- **Network**: Gigabit Ethernet

---

## Preparation

### Required Materials
- USB 3.0 flash drive (FAT32, MBR partition table)
- Paper clip (for reset button)
- Ethernet connection

### Downloads
1. Visit the [fox-exe repository](https://fox-exe.ru/WDMyCloud/WDMyCloud-Home/Debian/).
2. Download `wd-mycloud-home-debian.7z`.
3. Extract the contents to the root of your USB drive. Ensure the `/omv` folder exists with `.tar.gz` files.

---

## Installation Procedure

### Phase 1: Boot from USB
1. Power down the WDMCH and unplug the power adapter.
2. Insert the prepared USB drive into the rear USB port.
3. **Important**: Use a paper clip to depress and **hold the reset button**.
4. Reconnect power while holding the reset button.
5. **Hold for 20-40 seconds** until the front LED stops flashing rapidly and stays solid white.
6. Release the reset button. The device will boot into the Debian installer from the USB.

### Phase 2: Initial SSH Configuration
1. Find the device IP (hostname `wdmch` or via router DHCP).
2. Connect via SSH:
   ```bash
   ssh root@<device-ip>
   # Default password: root
   ```
3. Change the root password immediately: `passwd`
4. Update packages:
   ```bash
   apt update && apt upgrade -y
   ```

### Phase 3: Install OpenMediaVault
Execute the pre-included installation script:
```bash
/root/installomv6.sh
```
The script takes 10-20 minutes. The device will **automatically reboot** when finished.

---

## Post-Installation

### Access the Web Interface
1. Navigate to `http://<device-ip>` in your browser.
2. **Default Credentials**:
   - **Username**: `admin`
   - **Password**: `openmediavault`

> [!IMPORTANT]
> Change the admin password immediately under **Settings** → **General**.

### Troubleshooting

#### Salt Configuration Errors
If the script hangs at "Setting up Salt environment":
```bash
apt-get install -y python3-psutil
/root/installomv6.sh
```

#### Boot Loops
If the device reboots continuously, ensure the USB drive was formatted correctly (FAT32/MBR) and the files were extracted properly to the root. Perform a fresh 40-second reset boot.

---

## Resource Management
The WDMCH only has 1GB of RAM. To maintain performance:
- Avoid running more than 2-3 Docker containers.
- Disable unused services (DLNA, etc.).
- Monitor temperatures in the small enclosure.
