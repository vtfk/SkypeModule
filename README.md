# Skype module

Functions for putting FrontEnd and Mediation servers in and out of Maintenance mode

# Installation
```
Install-Module -Name vtfk.SkypeMaintenanceMode
```

# Mediation Maintenance Mode

## A list of installed Mediation servers are dynamically added as the parameter ComputerName

### **Start**

```
Start-MaintenanceMode -ComputerName "Select-From-List"
```

### **Stop**

```
Stop-MediationMaintenance -ComputerName "Select-From-List"
```

# FrontEnd Maintenance Mode

## A list of installed FrontEnd servers are dynamically added as the parameter ComputerName

### **Start**

```
Start-FrontEndMaintenance -ComputerName "Select-From-List"
```

### **Stop**

```
Stop-FrontEndMaintenance -ComputerName "Select-From-List"
```

# FrontEndPool
Automatically retrieves and works on the FrontEndPool which has the CentralManagement service