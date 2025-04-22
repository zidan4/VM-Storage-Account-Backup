provider "azurerm" {
  features {}
}

# 1️⃣ Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-vm-backup"
  location = "East US"
}

# 2️⃣ Storage Account (for Azure Files)
resource "azurerm_storage_account" "st" {
  name                     = "stbackup${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  number  = true
  special = false
}

resource "azurerm_storage_share" "fileshare" {
  name                 = "vmbackupshare"
  storage_account_name = azurerm_storage_account.st.name
  quota                = 50
}

# 3️⃣ Virtual Network & Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-backup"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-backup"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 4️⃣ Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "nic-backup-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 5️⃣ Linux VM (with Azure Files mount via custom_data)
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-backup"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  # cloud-init script to mount the fileshare at /mnt/backup
  custom_data = base64encode(<<-EOF
                #!/bin/bash
                apt-get update
                apt-get install -y cifs-utils
                mkdir -p /mnt/backup
                mount -t cifs //${azurerm_storage_account.st.name}.file.core.windows.net/vmbackupshare /mnt/backup \\
                  -o vers=3.0,username=${azurerm_storage_account.st.name},password=${azurerm_storage_account.st.primary_access_key},dir_mode=0777,file_mode=0777
                EOF)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}
