#  Terraform OCI VM & VCN Setup
[![Terraform](https://img.shields.io/badge/Terraform-v1.5%2B-blue.svg)](https://www.terraform.io/)
[![OCI Provider](https://img.shields.io/badge/OCI%20Provider-v5%2B-orange.svg)](https://registry.terraform.io/providers/hashicorp/oci/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---
This Terraform module provisions the **Automatation of VM creation with SSH access alongside private Virtual Cloud Network (VCN)** in Oracle Cloud Infrastructure (OCI).

---
Overview This module creates:    
- **1 Virtual Cloud Network (VCN)**  
  CIDR: `172.16.0.0/20`

- **1 Public Subnet**  
  CIDR: `172.16.1.0/24`

- ** X amount of Ubuntu VMs**  
  OS: Ubuntu 22.04 or 24.04 (latest canonical images)  
  Shape: `VM.Standard.E2.1.Micro` or `VM.Standard2.1` (Free Tier eligible)  

- **Full Internet Access**  
  - Internet Gateway  
  - Route Table with default route `0.0.0.0/0 → IGW`

- **SSH-ready Security Rules**  
  - Security List allows TCP/22 from `0.0.0.0/0`  
  - Ephemeral Public IPs automatically assigned
---


## Prerequisites
| Requirement | Details |
|-----------|---------|
| **OCI Account** | Free Tier or Paid [](https://www.oracle.com/cloud/) |
| **Terraform** | `v1.5+` |
| **OCI CLI** | Latest version |
| **OS** | Tested on **Ubuntu 22.04+** (VM or local) |
## Install Terraform (Ubuntu/Debian)
```bash
sudo apt update && sudo apt install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```
## OCI Setup

### 1. Create a Dedicated Compartment

1. Log in to the **OCI Console**  
2. Navigate to **Identity & Security → Compartments**  
3. Click **Create Compartment**  

   **Fill in the details:**  
   - **Name:** `terraform-vcn-demo`  
   - **Description:** `Compartment for Terraform VCN & VM demo`  
   - **Parent Compartment:** (leave default or select your root)  

4. Click **Create Compartment**  
5. **Copy the Compartment OCID** — you’ll need it in `terraform.tfvars`

   ![Create Compartment](https://github.com/user-attachments/assets/6df370d6-7e62-467c-b394-a5a7b00092e1)  
   ![Compartment OCID](https://github.com/user-attachments/assets/3817f7d4-44ba-4a4a-91ee-88d591f71daa)

---


### Step 1: Set up OCI CLI
Before running Terraform, configure the OCI CLI with your Oracle Cloud credentials. Run:
 ```bash
   $ oci setup config
```
This will create a `~/.oci/config` file. You need to edit this file with your personal OCI details.

### Step 2: Edit the config file
Navigate to the `~/.oci` directory and open the `config` file in a text editor:
 ```bash
   $ cd ~/.oci
   $ sudo nano config
```
The file should look something like this:

- `user`: Your OCI user OCID (found in the OCI Console).
- `fingerprint`: The public SSH key fingerprint you will generate.
- `key_file`: The path to your private SSH key (`oci_api_key.pem`).
- `tenancy`: Your OCI tenancy OCID.
- `region`: Your Oracle Cloud region (e.g., `us-ashburn-1`).

### Step 3: Generate an SSH key pair
Generate an SSH key pair to authenticate with OCI and add the public key to your Oracle Cloud account:
```bash
   $ ssh-keygen -t rsa -b 2048 -f ~/.oci/oci_api_key.pem
   $ cat ~/.oci/oci_api_key.pem
```
Take the output from `cat ~/.oci/oci_api_key.pem.pub` and add this to your public API key in OCI **Identity > API Keys**.
Upload the public key in OCI Console → Identity & Security → Users → [Your User] → API Keys → 
<img width="1910" height="560" alt="image" src="https://github.com/user-attachments/assets/28daa9b7-7412-4e67-9029-9fe21b63f01a" />

This will have the fingerprint ID that will be used in your main.tf credentials for "fingerprint". 

### Step 3.5: Generate an SSH key pair within ~/.ssh 
```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/my_oci_key -N ""
```
This SSH key is meant to be used for the VMs to link your personal machine to them. DO NOT LOSE THIS.
These keys will be located in ~/.ssh/my_oci_key.pub

### Optional Step *skip if you want* -- for Custom OCID Image from Bucket


OCI accepts the following formats for importing custom boot disk images:

- **`QCOW2`** (`.qcow2` files)  
  This is the **preferred format** for KVM-based images. It supports compression and is commonly used with tools like `qemu-img`.  
  No specific sub-version is mandated, but ensure compatibility with QEMU (e.g., QCOW2 version 2 or 3 works well).

- **`VMDK`** (`.vmdk` files)  
  This is the VMware format. **Only the following sub-types are supported**:
  - `monolithicSparse` (single growable disk, often called "single-file VMDK")
  - `streamOptimized` (compressed, stream-optimized single-file VMDK — ideal for uploads)

  **Unsupported VMDK types**:
  - Multi-file VMDKs
  - Split volumes
  - Disks with snapshots
  - Formats like `twoGbMaxExtentSparse` or `twoGbMaxExtentFlat`

#### Recommended Official Sources

| Distribution   | Download Link                                              |
|----------------|------------------------------------------------------------|
| Debian Cloud   | https://cloud.debian.org/images/cloud/                     |
| Ubuntu Cloud   | https://cloud-images.ubuntu.com/                           |
| Rocky Linux    | https://dl.rockylinux.org/pub/rocky/                       |
| AlmaLinux      | https://repo.almalinux.org/almalinux/                      |
| Fedora Cloud   | https://download.fedoraproject.org/pub/fedora/linux/releases/ |

**Recommendation:** Use the latest **Debian Bookworm** (Debian 12) QCOW2 image. Navigate from https://cloud.debian.org/images/cloud/  -> Bookworm (Debian) -> Latest Version Out

#### Upload to Object Storage

1. **Storage > Buckets > Create Bucket**  
   ![Create Bucket](https://github.com/user-attachments/assets/59d446d8-bf17-44cc-8bdc-46b863920515)

2. **Upload Object** → Select your `.qcow2` or `.vmdk` file  
   ![Upload Image](https://github.com/user-attachments/assets/97060031-4400-48ad-a8a1-1ea0f82ea89e)

3. After upload, go to **Compute > Custom Images > Create Custom Image** and select the object from your bucket.



Index for Storage > Buckets > Create a Bucket
<img width="1861" height="560" alt="Screenshot 2025-11-10 171724" src="https://github.com/user-attachments/assets/59d446d8-bf17-44cc-8bdc-46b863920515" />
Upload Objects > Import your OCI Image file.  
<img width="1807" height="863" alt="Screenshot 2025-11-10 171903" src="https://github.com/user-attachments/assets/97060031-4400-48ad-a8a1-1ea0f82ea89e" />

## You will have to include your own OCID within the Main.tf and code the image to directly input from your Bucket to choose your own OS-- the current main.tf code is not meant for custom images uploaded from OCID Buckets (Ubuntu) but from standard images from OCI avaliable for ease of access to the current users using this.

## [Go to this step if you skipped the optional Bucket Image]

**Deploy with Terraform**
1. Initialize the Terraform configuration:
```bash
   $ terraform init
```
<img width="736" height="285" alt="image" src="https://github.com/user-attachments/assets/ed88cc10-0a8f-43b3-8964-853f1e85338b" />



4. Apply the configuration to create the VCN:
```bash
# 1. Deploy (just pass compartment ID)
terraform init
terraform apply -var="compartment_id=ocid1.compartment.oc1..aaaa..."

Optional Syntax:
# 2. VMs with default names
terraform apply -var="compartment_id=..." -var="vm_count=5"

# 3. VMs with custom names  
terraform apply -var="compartment_id=..." -var='vm_names=["web1","db1","app1"]'

# 4. Both together
terraform apply -var="compartment_id=..." -var="vm_count=5" -var='vm_names=["web1","db2","app1","cache1","cache2"]'
```
<img width="394" height="952" alt="Screenshot 2025-11-28 124044" src="https://github.com/user-attachments/assets/eebbc651-40c6-46b0-8bc3-df96b9023bb1" />


**Verify VMs and SSH functions**:
<img width="1919" height="520" alt="image" src="https://github.com/user-attachments/assets/b30d653e-a191-4dfe-bb2c-8d856a6bf57c" />

<img width="1174" height="927" alt="image" src="https://github.com/user-attachments/assets/d36f123f-9007-4638-93d6-2a8536325fa7" />

-Ignore the "Debian" comment-- I previously tried to upload Debian Images and forgot to change it back to Ubuntu. Edited this in the main.tf. 
-Full IP is hidden to protect my personal public IPs made for the VMs. 


