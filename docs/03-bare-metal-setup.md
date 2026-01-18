# Bare Metal Setup Guide

This guide provides step-by-step instructions for setting up the homelab hardware from scratch.

## 1. OPNsense (Topton N100)

The Topton N100 acts as the core gateway and router.

### Preparation
1. Download the latest OPNsense image (vga or dvd) from [opnsense.org](https://opnsense.org/download/).
2. Flash the image to a USB drive using Etcher or `dd`.

### Installation
1. Boot the Topton N100 from the USB drive.
2. Login with `root` / `opnsense`.
3. Select **8. Shell** to run the installer: `/usr/local/etc/rc.initial.install`.
4. Choose **ZFS** for the file system.
5. Follow the prompts and reboot.

### Initial Configuration
1. **Interfaces**: Assign `igc0` as WAN and `igc1` as LAN.
2. **WAN Setup**: Connect to the Fritzbox LAN. Set to DHCP or Static (`10.1.10.2`).
3. **LAN Setup**: Set IP to `10.10.0.1`.
4. **Power Savings**: Navigate to **System -> Settings -> Miscellaneous**. Enable `powerd` and set to `adaptive`.
5. **DNS**: Configure Unbound as per [Split DNS Guide](01-networking-opnsense-fritzbox.md).

---

## 2. Talos Linux (Esprimo & Minisforum)

Talos Linux is an immutable OS for Kubernetes.

### Preparation
1. Download the latest Talos Metal image from [talos.dev](https://www.talos.dev/).
2. Flash to a USB drive.

### Bios Settings (Critical)
1. **Boot Mode**: UEFI only.
2. **SATA Mode**: AHCI.
3. **Virtualization**: VT-x and VT-d enabled.
4. **Wake-on-LAN**: Enabled (especially on Minisforum edge nodes).
5. **Auto-Power-On**: Set to "Last State" or "Always On".

### Installation
1. Boot the node from the USB drive.
2. The node will enter "Maintenance Mode".
3. From your management machine, use `talosctl` to apply the generated configuration:
   ```bash
   # Example for Core Node 1
   talosctl apply-config --insecure --nodes 10.10.0.11 --file talos/controlplane-talos-core-01.yaml
   ```
4. Talos will install to the NVMe disk (`/dev/nvme0n1`) and reboot.

---

## 3. OpenMediaVault (WD MyCloud Home)

The WD MyCloud Home is used as a backup target.

### Preparation
Note: This assumes the device has already been "cracked" or flashed to a standard Debian system.
1. Install OMV on top of Debian:
   ```bash
   wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash
   ```

### Configuration
1. **Network**: Set static IP in the Fritzbox range (or cluster range if connected to OPNsense).
2. **Storage**: Mount the internal 8TB HDD.
3. **Services**:
    - **NFS**: Enable NFS and create a share for Longhorn backups.
    - **S3 (MinIO)**: (Optional) Install MinIO plugin for S3-compatible backups.
4. **Backup Target**: Point Longhorn to the OMV IP and NFS path.

### Energy Tuning
- Enable HDD spindown in OMV settings to save power when backups are not running.
