The MD5HASH for these executables are:

14b52f155bc582bcc251ad93eacd4125  mochimo-winminer.exe
258253063d1dedfcea4101423ed3ccac  update-monitor.exe

This software is offered with no warranty, and is subject to the terms and conditions of the license, which can be found here:
https://github.com/mochimodev/mochimo/blob/master/LICENSE.PDF

Use at your own risk.

You may start the miner by double-clicking the executable "mochimo-winminer.exe".  On some systems you may have to configure the system
to allow the other executable update-monitor.exe to run.  Please visit the Mochimo Wiki Page for the Headless Windows Miner for more information: http://www.mochiwiki.com/w/index.php/Windows_Miner

From the command line, you have other options:

Usage: mochimo-winminer [-option -option2 . . .]
		All command-line switches are optional.  If left default this miner will pull a full node
		IP list from mochimap.net, and begin mining.  If you don't have a maddr.dat address file
		in this directory, it will create one for you called maddr.dat.
		Options:
		           -aXXX.XXX.XXX.XXX set IP address to pull block from, exammple: 65.151.42.11
		           -pN set TCP port to N (default: 2095)
		           -mFILENAME.ADDR mining address is in file (default: maddr.adr)
		           -wURL Pull core ip list file from URL (default: https://www.mochimap.net:8443/)
		           -cFILENAME.LST read core ip list from file (default: fullnodes.lst)
		           -tN set Trace to N
		           -h  this message
