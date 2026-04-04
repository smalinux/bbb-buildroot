// SPDX-License-Identifier: GPL-2.0
/*
 * hello.c — minimal out-of-tree kernel module example for the BBB.
 *
 * Prints a message on module load and unload. Used to verify the
 * kmodules/ build infrastructure end-to-end:
 *   1. buildroot compiles it against the configured kernel
 *   2. the .ko is installed into /lib/modules/<ver>/extra/
 *   3. depmod indexes it so `modprobe hello` works
 *   4. load/unload produces the expected dmesg output
 */

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static int __init hello_init(void)
{
	pr_info("hello: loaded on BeagleBone Black\n");
	return 0;
}

static void __exit hello_exit(void)
{
	pr_info("hello: unloaded\n");
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Sohaib Mohamed");
MODULE_DESCRIPTION("Minimal out-of-tree kernel module example for BBB");
MODULE_VERSION("1.0");
