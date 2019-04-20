# Mochimo Headless Windows Miner

Mochimo Project - Headless Windows Miner Development Repository

All contents of this respository are subject to the license terms and conditions associated with the Mochimo Cryptocurrency Engine.
See LICENSE.PDF.

You must read and agree to the LICENSE.PDF file prior to compiling or running our code.

JOIN THE COMMUNITY!

Please follow the below link to join in the discussion of mochimo with the rest of the developer and beta testing community:

https://discord.gg/EHFqS5s

The contents of this repository are copyright 2019 Adequate Systems, LLC.  All Rights Reserved.
Please read the license file in the package for additional restrictions.

Contact: support@mochimo.org

## Compilation Instructions
*Disclaimer: When downloading/installing the Cuda Toolkit, ensure:*
```
- compatibility with your Nvidia graphics card/s
- compatibility with you version of Visual Studio
- and also that the installation isn't going to overwrite your
  existing driver for a driver that just is now incompatible
  with your graphics card/s
```
*If you are a wizard who is 110% sure that your Visual Studio and Cuda Toolkit installation is properly installed on your system, skip to step 2.*
1. Download and install Visual Studio 2017 and a Cuda Toolkit IN THAT ORDER.
2. Open a Visual Studio Developer Command Prompt compatible with your system (x86/x64)
3. Clone the repository with command: `git clone https://github.com/mochimodev/winminer.git`
~~4. Navigate to your `winminer\winminer_v1\winminer` folder~~
~~5. Compile `mochimo-winminer.exe` with command: `nvcc -arch=sm_37 -o mochimo-winminer.exe winminer.cpp trigg.cu`~~
~~6. Move `mochimo-winminer.exe` binary to the `\winminer\binaries` folder~~
~~7. Navigate to your `winminer\winminer_v1\updatemonitor` folder~~
~~8. Compile `update-monitor.exe` with command: `cl /Feupdate-monitor.exe updatemonitor.cpp`~~
~~9. Move `update-monitor.exe` binary to the `\winminer\binaries` folder~~
4. Navigate to your `winminer\winminer_v1` folder
5. Compile with command: `msbuild mochimo-winminer.sln`
6. You can now find your miner in the `winminer\winminer_v1\x64\Release` folder
10. Run the miner with your fingers crossed.

