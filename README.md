# wincamcfg.ps1
Reimplements the repo https://github.com/andrewj-t/wincamcfg as a .ps1 script. Created by proompting CoPilot a few times.

# Usage:
.\wincamcfg.ps1 list [--output text|json]
.\wincamcfg.ps1 get --camera <index|all> [--output text|json]
.\wincamcfg.ps1 set --camera <index|all> --property <name> --value <value>
.\wincamcfg.ps1 version

# Example:

.\wincamcfg.ps1 set --camera all --property PowerlineFrequency --value 60Hz

Output with 2 cameras connected:
Set PowerlineFrequency to 60Hz on camera 0.
Set PowerlineFrequency to 60Hz on camera 1.
