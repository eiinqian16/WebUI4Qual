This repository is for fixing Web UI on Qualcomm boards. 

Installation instructions:
1. Create Makefile in /package/system/webUI
2. Copy Makefile contents into the Makefile directory
3. Enable webUI configuration: echo "CONFIG_PACKAGE_webUI=y" >> .config
4. Recompile firmware: make V=s
