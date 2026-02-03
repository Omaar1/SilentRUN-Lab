# SilentRUN Lab Documentation

## Work Done
We have configured a specialized lab environment for Red Team exercises, focusing on Active Directory (AD), ADCS, and SCCM attack vectors.

### Resource Optimization
To ensure the lab runs smoothly on your host (approx. 16GB RAM), we significantly optimized the Virtual Machine (VM) resource allocations:

*   **RootDC**: Reduced to 2 vCPUs and 2048 MB RAM (from 4 vCPU/4096 MB).
*   **ADCS Server**: Reduced to 1 vCPU and 1024 MB RAM (from 2 vCPU/2048 MB).
*   **SCCM Server**: Reduced to 2 vCPUs and 6144 MB RAM (from 6 vCPU/8192 MB).
*   **Other Servers (server1)**: Disabled to conserve resources.

Total Lab RAM Usage: ~9.2 GB (leaving ~6-8 GB for the host OS).

## Prerequisites
Before running the lab, ensure the following are installed:

1.  **VirtualBox**: The hypervisor used to run the VMs.
2.  **Vagrant**: Only the `vagrant` CLI tool is needed.
3.  **Vagrant Plugins**:
    *   `vagrant-winrm`: Enables communication with Windows VMs.
    *   `vagrant-windows-sysprep`: Handles Windows initialization.
    *   *Installed via:* `vagrant plugin install vagrant-windows-sysprep`

**Note on Large Downloads**:
*   The script will automatically download **MECM (SCCM)** (1.2GB) and **SQL Server** if they are not present.
*   The MECM installer is a self-extracting executable which the script will unpack automatically.
*   If you have a slow connection, you can manually download `MEM_Configmgr_Eval.exe` and place it in `sharedscripts/services/SCCM/MECM_Setup/` to save time during provisioning.

## Running Instructions
The lab is managed via Vagrant.

1.  **Start the Lab**:
    Open a terminal in the `d:\redInvoke\lab-creation` directory and run:
    ```powershell
    vagrant up
    ```
    This command will download the base box (Windows Server 2019), import it, and provision all three servers automatically. This process can take 30-60+ minutes depending on internet speed and disk I/O.

2.  **Accessing VMs**:
    *   Network Range: `10.10.10.0/24`
    *   **DC**: `10.10.10.100` (silent.run)
    *   **ADCS**: `10.10.10.103`
    *   **SCCM**: `10.10.10.104`

## Attack Vectors
The SCCM server is pre-configured with several vulnerabilities designed for "SilentRUN" style attack simulations.

### 1. CRED-1 (PXE Boot & NAA)
*   **Description**: The SCCM server has PXE boot enabled without password protection.
*   **Vulnerability**: Attackers can boot from the network and retrieve the Network Access Account (NAA) credentials.
*   **Account Exposed**: `SILENT\sccm_naa`

### 2. CRED-2 (Task Sequence)
*   **Description**: A task sequence is deployed to the "All Systems" collection.
*   **Vulnerability**: Exposed task sequence variables or sensitive data within the task sequence itself.

### 3. Client Push Installation
*   **Description**: Client push is enabled for all systems.
*   **Vulnerability**: Using `SILENT\sccm_cpia` account. If an attacker controls a machine where the client is pushed, they might dump credentials (though more complex to exploit than NAA).

### 4. Anonymous Distribution Point (DP) Looting
*   **Description**: A "vulnerable package" is deployed.
*   **Vulnerability**: Distribution Points might allow anonymous access or contain sensitive data in packages.

## To-Do List (Future Work)
- [ ] **Verify Attack Paths**: Manually test each attack vector (CRED-1, CRED-2, etc.) to confirm exploitability.
- [ ] **Lab Expansion**: Re-enable `server1` or add workstation nodes (`wks_name`) if host resources permit (e.g., upgrading RAM to 32GB).
- [ ] **Simulation Scripts**: Write automated attack scripts (e.g., using Python/Impacket) to demonstrate the vulnerabilities.
- [ ] **Documentation**: Create a step-by-step "Walkthrough" guide for exploiting each vulnerability.
