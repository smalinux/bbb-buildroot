Issue:::

INFO: hdimage(sdcard.img): adding primary partition '[MBR]' ...
INFO: hdimage(sdcard.img): writing MBR
INFO: cmd: "rm -rf "/src/bbb-buildroot/output/build/genimage.tmp/"" (stderr):
Generating SWUpdate package (version 0.1.0)...
sw-description
rootfs.ext4
3 blocks

OTA update package: /src/bbb-buildroot/output/images/update.swu
make[1]: Leaving directory '/src/bbb-buildroot/buildroot'

Output:
  SD card image: /src/bbb-buildroot/output/images/sdcard.img
  OTA package:   /src/bbb-buildroot/output/images/update.swu

Uploading to 192.168.0.98:8080...
curl: (22) The requested URL returned error: 404
Ubuntu@bbb-buildroot $
Ubuntu@bbb-buildroot $ ssh root@192.168.0.98 'ps aux | grep swupdate'
ssh: connect to host 192.168.0.98 port 22: Connection refused
Ubuntu@bbb-buildroot $
Ubuntu@bbb-buildroot $ ssh root@192.168.0.98 'swupdate -v -w "-r /var/www/swupdate -p 8080"'
ssh: connect to host 192.168.0.98 port 22: Connection refused

claude:::

● The SWUpdate web API endpoint has changed. Modern SWUpdate uses /upload under the /api path.
  Let me check the exact API.

● Explore(Find SWUpdate upload API)
  ⎿  Done (18 tool uses · 25.9k tokens · 32s)
  (ctrl+o to expand)

● The endpoint /upload matches SWUpdate's source code, so the URL is correct. The 404 likely
  means SWUpdate's web server isn't running on the board. Let me check if there's an init
  script to start it.

  Searched for 5 patterns, read 4 files (ctrl+o to expand)

● The init infrastructure looks correct - buildroot installs S80swupdate which starts the web server on port 8080. The 404 means the board is responding on that port but the endpoint isn't
  found.

  Can you SSH into the board to check if SWUpdate is actually running?

  ssh root@192.168.0.98 'ps | grep swupdate; echo "---"; ls /usr/lib/swupdate/conf.d/'

  The most common causes of this 404:

  1. SWUpdate is not running — the web server hasn't started, and something else (or a bare mongoose) is listening on 8080
  2. The web server args aren't being picked up — the 10-mongoose-args config file isn't installed to /usr/lib/swupdate/conf.d/, so SWUpdate starts without -w (no web server)

  To verify and fix, try SSHing in and running:

  # Check if swupdate is running with web server
  ssh root@192.168.0.98 'ps aux | grep swupdate'

  # Check if the config file exists
  ssh root@192.168.0.98 'cat /usr/lib/swupdate/conf.d/10-mongoose-args'

  # Try manually starting with web server
  ssh root@192.168.0.98 'swupdate -v -w "-r /var/www/swupdate -p 8080"'

  If SWUpdate is running but without the -w flag, the web upload endpoint won't exist — that's your 404.

