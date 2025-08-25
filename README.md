# 🚀 Azure Automation Hub

[![Azure](https://img.shields.io/badge/Azure-Automation-blue?style=flat-square&logo=microsoft-azure)](https://azure.microsoft.com/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?style=flat-square&logo=powershell)](https://docs.microsoft.com/powershell/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Contributions Welcome](https://img.shields.io/badge/Contributions-Welcome-brightgreen?style=flat-square)](CONTRIBUTING.md)
[![GitHub stars](https://img.shields.io/github/stars/a-ariff/azure-automation-hub?style=flat-square)](https://github.com/a-ariff/azure-automation-hub/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/a-ariff/azure-automation-hub?style=flat-square)](https://github.com/a-ariff/azure-automation-hub/network)

> **Comprehensive Azure automation scripts and runbooks for user management, device monitoring, and enterprise IT operations**

## 📋 Overview

The Azure Automation Hub is a centralized repository containing production-ready PowerShell runbooks, ARM/Bicep templates, and automation scripts designed for enterprise Azure environments. This collection focuses on streamlining common IT operations, user lifecycle management, device compliance monitoring, and automated reporting.

## ✨ Key Features

### 👥 User Management Automation
- **Automated User Provisioning**: Create users across Active Directory and Azure AD
- **Bulk User Operations**: Mass user creation, updates, and deprovisioning
- **Group Management**: Automated security group assignments and management
- **License Assignment**: Automated Microsoft 365 license distribution
- **Offboarding Workflows**: Complete user deprovisioning with audit trails

### 📱 Device Monitoring & Compliance
- **Device Health Monitoring**: Real-time device status and compliance checking
- **Intune Integration**: Device enrollment and policy compliance automation
- **Security Baseline Enforcement**: Automated security configuration deployment
- **Patch Management**: Automated update deployment and reporting
- **Inventory Tracking**: Comprehensive device and software inventory

### 📊 Automated Reporting
- **Azure Cost Analysis**: Automated cost reporting and optimization recommendations
- **Security Compliance Reports**: Regular compliance status and audit reports
- **User Activity Analytics**: Login patterns and usage statistics
- **Device Utilization Reports**: Hardware usage and lifecycle management
- **Custom Dashboard Creation**: Automated Power BI dashboard updates

### 🏗️ Infrastructure as Code
- **ARM Templates**: Reusable infrastructure deployment templates
- **Bicep Modules**: Modern infrastructure-as-code implementations
- **Resource Group Management**: Automated resource organization
- **Policy Assignments**: Governance and compliance policy automation
- **Tag Management**: Consistent resource tagging strategies

## 📁 Repository Structure

```
azure-automation-hub/
├── 📂 runbooks/              # PowerShell automation runbooks
│   ├── user-management/      # User lifecycle automation
│   ├── device-monitoring/    # Device compliance & monitoring
│   └── reporting/           # Automated reporting scripts
├── 📂 device-monitoring/     # Device monitoring solutions
│   ├── intune-scripts/      # Microsoft Intune automation
│   ├── compliance-checks/   # Device compliance validation
│   └── inventory/          # Asset tracking and inventory
├── 📂 templates/            # ARM & Bicep templates
│   ├── arm/                # Azure Resource Manager templates
│   ├── bicep/              # Bicep infrastructure modules
│   └── policies/           # Azure Policy definitions
├── 📂 docs/                # Documentation and guides
│   ├── getting-started/    # Setup and configuration guides
│   ├── best-practices/     # Implementation best practices
│   └── troubleshooting/    # Common issues and solutions
└── 📂 examples/            # Sample implementations and demos
    ├── quick-start/        # Ready-to-use examples
    └── advanced/           # Complex scenario implementations
```

## 🚀 Quick Start

### Prerequisites
- Azure subscription with appropriate permissions
- Azure Automation Account
- PowerShell 5.1 or later
- Azure PowerShell module installed
- Microsoft Graph PowerShell SDK (for Azure AD operations)

### Basic Setup
1. **Clone the repository**:
   ```bash
   git clone https://github.com/a-ariff/azure-automation-hub.git
   cd azure-automation-hub
   ```

2. **Import runbooks to Azure Automation**:
   - Navigate to your Azure Automation Account
   - Import desired runbooks from the `/runbooks` folder
   - Configure required variables and credentials

3. **Deploy templates**:
   ```bash
   # Deploy ARM template
   az deployment group create --resource-group myRG --template-file templates/arm/user-management.json
   
   # Deploy Bicep template
   az deployment group create --resource-group myRG --template-file templates/bicep/monitoring.bicep
   ```

## 🔧 Configuration

### Required Azure Automation Variables
```powershell
# User Management
TenantId              # Azure AD Tenant ID
SubscriptionId        # Azure Subscription ID
ResourceGroupName     # Target Resource Group

# Notification Settings
NotificationEmail     # Alert recipient email
SMTPServer           # SMTP server for notifications
TeamsWebhookURL      # Microsoft Teams webhook URL
```

### Required Credentials
- **Azure Service Principal**: For Azure resource management
- **Microsoft Graph API**: For Azure AD operations
- **Exchange Online**: For mailbox management (if applicable)

## 📚 Documentation

- [🏃 Getting Started Guide](./docs/getting-started/README.md)
- [⚡ Runbook Documentation](./docs/runbooks/README.md)
- [🏗️ Template Usage Guide](./docs/templates/README.md)
- [🔧 Configuration Reference](./docs/configuration/README.md)
- [🛠️ Troubleshooting Guide](./docs/troubleshooting/README.md)

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting pull requests.

### Development Workflow
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- 📚 Check the [Documentation](./docs/) for detailed guides
- 🐛 Report bugs via [GitHub Issues](https://github.com/a-ariff/azure-automation-hub/issues)
- 💬 Join discussions in [GitHub Discussions](https://github.com/a-ariff/azure-automation-hub/discussions)
- 📧 Email support: [support@example.com](mailto:support@example.com)

## ⭐ Show Your Support

If this project helps you, please give it a ⭐ star on GitHub!

---

**Made with ❤️ for the Azure community**
