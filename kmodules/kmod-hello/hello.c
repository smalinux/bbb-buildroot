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
#include <linux/version.h>
#include <generated/utsrelease.h>

/*
 * Kernel-version compat shim — demonstrates the pattern out-of-tree
 * modules use to adapt to API changes across kernel versions. Real
 * drivers use this for things like platform_driver.remove, which
 * changed its return type from int to void in 6.11. Here we just
 * label the era for the log message.
 *
 * See doc/kernel-modules-versioning.md for the full rationale.
 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
#define HELLO_KERNEL_ERA "6.11+"
#elif LINUX_VERSION_CODE >= KERNEL_VERSION(6, 6, 0)
#define HELLO_KERNEL_ERA "6.6..6.10"
#else
#define HELLO_KERNEL_ERA "pre-6.6"
#endif

static int __init hello_init(void)
{
	pr_info("hello: loaded on BeagleBone Black (built for %s, era %s)\n",
		UTS_RELEASE, HELLO_KERNEL_ERA);
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
