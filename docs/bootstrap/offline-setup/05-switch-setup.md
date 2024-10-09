# Switch Setup

## PCT6248

Connect the serial cable and plug the switch in.

When the boot menu appears, select `2`:

```{ .raw .no-copy }
Boot Menu Version: 3.3.18.1
Select an option. If no selection in 10 seconds then
operational code will start.


1 - Start operational code.
2 - Start Boot menu.
Select (1, 2): 2
```

In the Boot menu, select option `10` to clear all configuration:

```{ .raw .no-copy }
. . .
10 - Restore configuration to factory defaults (delete config files)
. . .

[Boot] 10
```

Wait for the switch to come online and show the console:

```{ .raw .no-copy }
console>
```

Now enter the privileged mode and copy the configuration file from the TFTP
server to the `running-config`:

```{ .raw .no-copy }
console> enable
```

```{ .raw .no-copy }
console# copy tftp://10.0.1.1/pct6248.cfg running-config


Mode.............................................. TFTP
Set TFTP Server IP................................ 10.0.1.1
TFTP Path......................................... ./
TFTP Filename..................................... pct6248.cfg
Data Type......................................... Config Script
Destination Filename.............................. running-config

Management will be blocked for the duration of the transfer
Are you sure you want to start? (y/n)
```

Hit the `y` key then `Enter` and the file will be downloaded and applied. Once
that is complete, copy the `running-config` to `startup-config` so you don't
have to manually download the file every time the switch boots:

```raw
console# copy running-config startup-config
```

Now exit:

```raw
console# exit
```

## PSS4810

Connect the serial cable to the switch and plug it in.

When bootup completes, it might try to pull the configuration automatically from
the TFTP server if there's no startup configuration. If so, then _that is what_ 
_we want_, and it's already in configured how it should be and the rest of this
section can be skipped.

If the switch boots into the conole, then enter the following:

```{ .raw .no-copy }
console> enable
```

```{ .raw .no-copy }
console# restore factory-defaults stack-unit all clear-all
```

After the switch reboots, it should start in Bare Metal Provisioning (BMP) mode.

If it does not, or if you want the switch to reboot into BMP every time it
starts, then apply the following:

Enter privileged mode:

```{ .raw .no-copy }
console> enable
```

Enter configuration mode:

```{ .raw .no-copy }
console# configure
```

Enter the `reload-type` configuration mode:

```{ .raw .no-copy }
console(conf)# reload-type
```

Set the `reload-type` to `bmp-reload`:

```{ .raw .no-copy }
console(conf-reload-type)# boot-type bmp-reload
```

Exit the `reload-type` configuration mode:

```{ .raw .no-copy }
console(conf-reload-type)# exit
```

Exit configuration mode:

```{ .raw .no-copy }
console(conf)# exit
```

Reload the switch:

```{ .raw .no-copy }
console# reload no-confirm
```
