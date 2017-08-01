# Introduction to the Lab Environment Standards

This guide describes the lab environment standards used by the SUSE Training organization. The reasons for these standards are many but essentially boil down to making sure we have a consistent way of doing things so that it will be easier to consume by the end user and easier to develop by the course developers. An added benefit to following these standards is that there are a number of tools that have and will be created that make developing and working with lab environments much quicker and easier. A list of these tools will be maintained at the end of this document and there may be additional documents that provide greater detail on using these tools.

# Usernames and Passwords

The usernames and passwords that exist in the lab VMs are at the discretion of the course developer based on the requirements for the courses. However, it is strongly recommended that the following two accounts exist in the VMs using the usernames and passwords provided (through the use of ‘geeko’ is starting to be discouraged).

**Root account:**
Username=root
Password=linux

**Regular user account:**
Username=geeko
Password=linux
UID=1000

# Networking

## Subnets and Network Names

The configuration of the networking in a lab environment is left to the discretion of the course developer based on the requirements for the course. It is strongly recommended that commonly used private subnets (i.e. 192.168.1.0/24, 10.0.0.0/24, etc.) be avoided. It is also recommended that the default Libvirt network (named default with a subnet of 192.168.100.0/24) be avoided. The name of the virtual network should be something that is descriptively relative to the course. 

(Example: The **admin** network in the OpenStack cloud course could be named **cloud-admin**)

## Virtual Bridge Names

Because it is possible that multiple lab environments can installed on a single lab machine at a time, there is a possibility of naming collisions between the virtual networks. It is strongly recommended that the network XML definition be edited so that the virtual bridge created by Libvirt, when the network is created, be named using a more descriptive name. The recommendation is to use the name of the virtual network as the name of the bridge.

**Example**: 
```
<name>**cloud-admin**</name>
...
  <ip address=’192.168.124.1’, netmask=’255.255.255.0’> 
  <bridge name=’**cloud-admin**‘ … />
...
```

For things like SUSECon sessions, because you can’t really know what the other sessions’ virtual networks are, it is suggested that you use a naming convention that includes your session ID (Example: **virbr-HO77572**). In the case where your session requires multiple networks, append the network number to the session ID separated by a **_** (Example: **virbr-HO77572_1** for the first network, **virbr-HO77572_2** for the second network, etc.).

## Network Definition XML File

The Libvirt virtual network definition XML file should be provided as part of the student media. This XML file can be created using the following command:

```
virsh net-dumpxml <NETWORK_NAME> > <NETWORK_NAME>.xml
```

The name of the file should be the name of the **<NETWORK_NAME>.xml** where **<NETWORK_NAME>** = the name of the virtual network (i.e. cloud-admin).

The following is an example of one of these network definition XML files:

**File name**: **cloud-admin.xml**

```
<network>**
  <name>cloud-admin</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='cloud-admin' stp='on' delay='0'/>
  <mac address='52:54:00:20:52:73'/>
  <domain name='cloud-admin'/>
  <ip address='192.168.124.1' netmask='255.255.255.0'>
  </ip>
</network>
```

## Multi Lab Machine Environments

It is possible to spread a lab environment for a single student across multiple lab machines. When doing this it will typically require a different networking configuration to allow the VMs to communicate with each other when they are running on different lab machines. This different networking environment typically consists of a secondary network connection between the lab machines with separate VLANs with corresponding Linux bridges attached to them running across this secondary network. These Linux bridges take the place of the Libvirt virtual networks that the VMs are typically connected to.

When providing for this multi lab machine environment, each VM will require an addition XML definition file that specifies these bridges instead of Libvirt networks. Both XML definition files are required (single lab machine and multi lab machine versions) and should reside in the VM specific directory in **/home/VMs/<COURSE_ID>/** (i.e. **/home/VMs/<COURSE_ID>/<NAME_OF_VM>/**).

(Where **<COURSE_ID>** is the course ID number).

To have the VM connect to these Linux bridges on the VLANs rather than the Libvirt networks, you edit the VM’s secondary multi lab machine specific XML definition (typically named **\<NAME_OF_VM>-multi_lm.xml**). In the network interface descriptions, change "network" to ‘bridge”. See the following example configuration snippets for the configuration changes. The values that need to be modified are bolded.

Example with Libvirt networks (original VM definition file):
```
...
    <interface type=network>
      <mac address='52:54:00:fd:d9:3a'/>
      <source network='cloud-admin'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
...
```

Example with Linux bridges (secondary multi lab machine VM definition file):
```
...
    <interface type=bridge>
      <mac address='52:54:00:fd:d9:3a'/>
      <source bridge='cloud-admin'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
...
```

The VLANs and Linux bridges attached to them that are used for these cross lab machine virtual networks can be created with YaST or can be automatically created using the lab environment installation framework.

# Virtual Machines

When creating virtual machines, the following guidelines should be followed:

## Virtual Machine Directory

All files related to a virtual machine should exist in a single directory and the name of the directory should be the name of the virtual machine (as defined in the virtual machine’s Libvirt XML file). These individual virtual machine specific directories should all be subdirectories of: **/home/VMs/<COURSE_ID>** 

Example: **/home/VMs/<COURSE_ID>/<NAME_OF_VM>/** 

(Where **<COURSE_ID>** is the course ID number or SUSECON session ID and  **<NAME_OF_VM>** is the name of the virtual machine as defined in the VM’s XML definition file).

The files in the individual virtual machine directory should include at least the following:

* Virtual machine XML definition file(s)
* Disk image files used by the VM

Example Virtual Machine Directory Structure:
```
/home/VMs/<COURSE_ID>/<NAME_OF_VM>/
                                  |-<NAME_OF_VM>.xml
                                  |-<NAME_OF_VM>-multi_lm.xml
                                  |-<NAME_OF_VM>-disk01.qcow2 
```
If you use Virt-Manager to create the new VM, it is easiest to manually create the VM directory and the disk image files in the directory first and then specify the disk image file during the installation. How to do this will be covered below.

## Virtual Machine XML Description

The virtual machine’s XML definition file should be named **<NAME_OF_VM>.xml** (where **<NAME_OF_VM>** is the name of the virtual machine as defined in the VM’s XML definition file).

The virtual machine’s XML definition file can be created using the following command:
```
virsh dumpxml <NAME_OF_VM> > /home/VMs/<COURSE_ID>/<NAME_OF_VM>/<NAME_OF_VM>.xml
```
After creating the VM’s XML definition file, you need to edit the file and remove the **<uuid>** and **<cpu>** sections as these will be auto-generated when the VM is registered with Libvirt on the lab machine. If the VM wasn’t originally created in the required directory (**/home/VMs/<COURSE_ID>/<NAME_OF_VM>/**), you will also need to edit the path to the disk images in the XML definition file to reside in this path.

## Virtual Machine Disks

Virtual machine disks should be of format QCOW2 when at all possible. The size of the disks should be as small as possible to meet the requirements of the course. (This helps keep the overall size of the student media smaller).

The disk image files should reside in the VM’s directory (**/home/VMs/<COURSE_ID>/<NAME_OF_VM>/**). It is important to note that if you are creating the VM using Virt-Manager, there is no option to create the images here.  You must first manually create the disk image in that directory using the **qemu-img** command and then, in Virt-Manager, select it as an existing disk image when creating the VM.

Example **qemu-img** command: 
```
qemu-img create -f qcow2 /home/VMs/<COURSE_ID>/<NAME_OF_VM>/disk0.qcow2 20G
```

# ISO Images

If your virtual machines require ISO images or if you want to provide ISO images to your students, the following guidelines should be followed:

## ISO Image Directory

All ISO images related to a course should reside in a single directory named: **/home/iso/<COURSE_ID>** 

_**Example**_: **/home/iso/<COURSE_ID>/my-iso.iso**

Or, if the ISO image will only be used by a single VM, the ISO image can reside in the VM’s directory (see Virtual Machine Directory above).

# Cloud Images

If your lab environment requires cloud images to be used or if you want to provide cloud images to your students, the following guidelines should be followed:

## Cloud Image Directory

All cloud images related to a course should reside in a single directory named: **/home/images/<COURSE_ID>** 

_**Example**_: **/home/images/<COURSE_ID>/my-cloud-image.qcow2** 

# Lab Environment Related Tools

## Lab Machine Image

A standard lab machine image based on openSUSE is provided for developing and running lab environments. This lab machine image auto logs in as a regular user named **tux** and is preconfigured for Libvirt/KVM, VirtualBox and Docker VMs/containers to be run as a regular user. It also has a number of other extras preconfigured such as additional GNOME Shell extensions and additional scripts for lab machine, lab environment and VM management. GNOME is the default desktop environment but XFCE is installed and configured to look similar to the GNOME environment.

The is a document named **README-Live_Image_Options** that covers how to install and use the Lab Machine Image in greater detail.

## Lab Environment Installer Framework

There is a lab environment installer framework that can be used to create installer packages for lab environments. These installer packages make installing, and equally important, removing lab environments much easier. Using the Installer Framework also allows for lab environments to be compartmentalized theoretically enabling multiple lab environments to be installed simultaneously and have them not step on each other.

There is a document named **GUIDE-Lab_Environment_Installer_Framework** that covers how to use the Lab Environment Installer Framework in greater detail.

## Scripts

There are a number of additional scripts that have been developed that can help make developing, modifying or otherwise working with lab environments easier. These scripts are typically included in the lab machine image (in **/usr/local/bin/**). These scripts are outlined here:

### backup_lab_env.sh

**Intro**:

This script is part of the Lab Environment Installer Framework but is also provided as part of the standard lab machine scripts because it is usable and useful outside of the Framework as well.

This script can be used to backup the current state of a currently installed lab environment. For the backup, it creates an installer package (using the Lab Environment Installer Framework) for the lab environment that includes archives of the current state of the VMs, ISO images, cloud images, course files, scripts, etc. These backups are created in **/install/courses/** and the directories that map to the backup/installer package are named using the following format: 

**<COURSE_ID>-backup-<DATE_STAMP>.<UNIX_TIME_STAMP>** 

**Usage**:
```
backup_lab_env.sh <course_id> [<archive_format>] 
```
**Detailed Description**:

By default VM archives are created using p7zip with the compression format of LZMA2. This can be overridden at the command line using the **<archive_format>**. The supported archive formats are:

Archive Format | Description
------------ | -------------
**7zma2** | p7zip with LZMA2 compression split into 2G files
**7z** | p7zip with LZMA compression split into 2G files
**7zcopy** | p7zip with no compression split into 2G files
**tar** | tar archive with no compression and not split
**tgz** | gzip compressed tar archive and not split
**tbz** | bzip2 compressed tar archive and not split
**txz** | xz compressed tar archive and not split


The p7zip formats are **strongly recommended** because they split the archive into smaller chunks that can reside on a FAT filesystem that is used by default when creating student media flash drives.

Because this script creates, as its backup, an installer package using the Lab Environment Installer Framework you can also use the script to create the initial installer package for a lab environment. As long as the VMs and ISO image (and cloud images) are in the appropriate directory structure as described earlier all you need to do is create a directory **~/scripts/****_COURSE_ID_****/** that contains the following files from the Installer Framework in the following directory structure (this matches the installed directory structure created when installing a course):
```
~/scripts/<COURSE_ID>/
		|-install_lab_env.sh
		|-remove_lab_env.sh
		|-backup_lab_env.sh
		|-restore-virtualization-environment.sh
		|-config/
			|-lab_env.cfg
			|-custom-functions.sh
			|-custom-install-functions.sh
			|-custom-remove-functions.sh
			|-libvirt.cfg/
				|-(your libvirt network XML definition files)
```
Once this directory structure is created, simply running the command:
```
 backup_lab_env.sh <COURSE_ID> 
```
will create a usable installer package in the **/install/courses/** directory.

### create-vm-archives.sh

**Intro**:

This scripts create archives of all VM directories inside a course directory. This should be run from inside the course VM directory (i.e. **/home/VMs/SOC101/** for a course named SOC101). 

**Usage**:
```
create-vm-archives.sh [<archive_format>] 
```
**Detailed Description**:

By default VM archives are created using p7zip with the compression format of LZMA2. This can be overridden at the command line using the **<archive_format>**. The supported archive formats are:

Archive Format | Description
------------ | -------------
**7zma2** | p7zip with LZMA2 compression split into 2G files
**7z** | p7zip with LZMA compression split into 2G files
**7zcopy** | p7zip with no compression split into 2G files
**tar** | tar archive with no compression and not split
**tgz** | gzip compressed tar archive and not split
**tbz** | bzip2 compressed tar archive and not split
**txz** | xz compressed tar archive and not split


### change-vm-disk-path.sh

**Intro**:

This script allows you to change the paths to the disks in the Libvirt XML VM definition files for all VMs in a course directory. This is particularly useful if you have change the name of the course directory, the name of the VM directory or have copied VMs from existing course into a new course.

**Usage**:
```
change-vm-disk-path.sh <course_vm_directory> <new_vm_directory_path>
```
**Detailed Description**:

For example, if I have a course named SOC101, according to the standards laid out previously, all of the VMs for that course should exist in a **/home/VMs/SOC101/** directory. Each of the VMs should be in their own directory (i.e. **/home/VMs/SOC101/SOC101-admin/**, **/home/VMs/SOC101/SOC101-controller01**, etc.) and those VM directories should contain the disk image for that MV as well as a Libvirt XML VM definition file. The VM definition files should be named the same as the VM directory (i.e. **/home/VMs/SOC101/SOC101-admin/SOC101-admin.xml**, etc.). This script updates the path for the disk images in these VM definition files.

### reset-vm-disk-image.sh 

**Intro**:

This script resets a VMs disk image in one of two ways. First, if the disk image has snapshots it reverts the disk back to the first snapshot and removes all other snapshots. Second, if the disk doesn’t have snapshots it deletes the disk image file and creates a new empty disk image file of the same type and size in the original file’s place.

Usage:
```
reset-vm-disk-image.sh <vm_dir> 
```
**Detailed Description**:

**WARNING** - This can be dangerous. It was designed to quickly reset empty VMs so that they can be reinstalled.

### backup-homedirs.sh

**Info**:

This script backups up the home directories of either all users on a machine or a specified user or a list of users. The backups are created in the **/home/backups/** directory as .tgz files.

It is particularly useful to run this command right after a machine has been installed to get clean backups of users’ home directories before the machine gets used.

**Usage**:
```
backup-homedirs.sh [<username> [<username> …]]*
```
### restore-homedirs.sh

**Info**:

This script restores backed up the home directories created by the **backup-homedir.sh** script. The script expects the backups to be .tgz files in the **/home/backups/** directory.

It is particularly useful to run this command right after a machine has been used by someone that has made significant changes to user’s environment such and keyboard layout, language, etc. It can also be useful when you want a known clean version of a home directory quickly..

**Usage**:
```
restore-homedirs.sh [<username> [<username> …]]
```
### remove-all-vnets.sh 

**Info**:

This script removes **all** Libvirt virtual networks that have been defined. This can be useful if you want to clean up a lab machine that has had lab environments installed on it that were not cleanly removed.

**Usage**:
```
remove-all-vnets.sh
```
### remove-all-vms.sh 

**Info**:

This script removes **all** Libvirt virtual machines that have been defined. This can be useful if you want to clean up a lab machine that has had lab environments installed on it that were not cleanly removed.

**Usage**:
```
remove-all-vms.sh
```
### cleanup-libvirt.sh 

**Info**:

This script removes **all** Libvirt virtual machines and virtual networks that have been defined. This can be useful if you want to clean up a lab machine that has had lab environments installed on it that were not cleanly removed.

**Usage**:
```
cleanup-libvirt.sh
```
### remove-all-courses.sh 

**Info**:

This script attempts to remove all courses that are currently installed that were installed using the Lab Environment Installer Framework. It does this by running all **remove_lab_env.sh** scripts for all courses found in **~/scripts/**.

**Usage**:
```
remove-all-courses.sh
```
### reset-lab-machine.sh

**Info**:

This script, as the name suggests, attempts to reset a lab machine by running the following scripts:
```
remove-all-courses.sh
remove-all-vms.sh
remove-all-vnets.sh
restore-homedirs.sh ${LAB_USER}
```

It should clean off all installed courses as well as any Libvirt VMs and Libvirt virtual networks that were manually created or not cleaned up by course removal scripts. When that is done, if a backup was made of the **${LAB_USER}** (by default **tux**) home directory, it restores the backup.

**Usage**:
```
reset-lab-machine.sh
```
### create-live-usb.sh 

**Info**:

This script creates bootable student media flash drives from a lab machine image ISO and course student media directories. Multiple Live ISO image can be specified and multiple source student media directories (or other files/directories) can be specified.

There is a document named **GUIDE-Student_Flash_Drive_Creation** that describes how to use this command in greater detail.


