#!/bin/bash
IP=192.168.1.244
S="ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no"
for i in $(seq 1 120); do
  live=$(timeout 15 $S root@$IP 'if [ -d /cdrom ]; then
      if grep -aqE "AutoinstallError|ValueError|Traceback" /var/log/installer/subiquity-server-debug.log; then echo FAILED;
      else grep -ao "finish: subiquity/Install/install: SUCCESS" /var/log/installer/subiquity-server-debug.log | tail -1 | grep -q SUCCESS && echo INSTALL_DONE || echo RUNNING; fi
    else echo REBOOTED_INSTALLED; fi' 2>/dev/null)
  case "$live" in
    FAILED)   echo "INSTALL FAILED - check /var/log/installer/ and /var/crash/"; exit 1 ;;
    INSTALL_DONE) echo "curtin install finished; awaiting reboot" ;;
    REBOOTED_INSTALLED) echo "host is up as the INSTALLED system"; exit 0 ;;
  esac
  if [ -z "$live" ]; then
    if timeout 10 $S -o ConnectTimeout=5 administrator@$IP 'hostname; ls -d /cdrom 2>/dev/null || echo NO_CDROM' 2>/dev/null | grep -q NO_CDROM; then
      echo "INSTALL COMPLETE - rebooted, reachable as administrator"; exit 0
    fi
  fi
  sleep 20
done
echo "watcher timed out after 40 min"; exit 2
